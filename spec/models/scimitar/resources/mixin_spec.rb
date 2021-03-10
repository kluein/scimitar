require 'spec_helper'

RSpec.describe Scimitar::Resources::Mixin do

  # ===========================================================================
  # Internal classes used in some tests
  # ===========================================================================

  class StaticMapTest
    include ActiveModel::Model

    attr_accessor :work_email_address,
                  :home_email_address

    def self.scim_resource_type
      return Scimitar::Resources::User
    end

    def self.scim_attributes_map
      return {
        emails: [
          {
            match: 'type',
            with:  'work',
            using: {
              value:   :work_email_address,
              primary: false
            }
          },
          {
            match: 'type',
            with:  'home',
            using: { value: :home_email_address }
          }
        ]
      }
    end

    def self.scim_mutable_attributes
      return nil
    end

    def self.scim_queryable_attributes
      return nil
    end

    include Scimitar::Resources::Mixin
  end

  class DynamicMapTest
    include ActiveModel::Model

    attr_accessor :groups

    def self.scim_resource_type
      return Scimitar::Resources::User
    end

    def self.scim_attributes_map
      return {
        groups: [
          {
            list:  :groups,
            using: {
              value:   :id,        # <-- i.e. DynamicMapTest.groups[n].id
              display: :full_name  # <-- i.e. DynamicMapTest.groups[n].full_name
            }
          }
        ]
      }
    end

    def self.scim_mutable_attributes
      return nil
    end

    def self.scim_queryable_attributes
      return nil
    end

    include Scimitar::Resources::Mixin
  end

  # ===========================================================================
  # Errant class definitions
  # ===========================================================================

  context 'with bad class definitions' do
    it 'complains about missing mandatory methods' do
      mandatory_class_methods = %w{
        scim_resource_type
        scim_attributes_map
        scim_mutable_attributes
        scim_queryable_attributes
      }

      mandatory_class_methods.each do | required_class_method |

        # E.g. "You must define ::scim_resource_type in #<Class:...>"
        #
        expect {
          klass = Class.new(BasicObject) do
            fewer_class_methods = mandatory_class_methods - [required_class_method]
            fewer_class_methods.each do | method_to_define |
              define_singleton_method(method_to_define) do
                puts 'I am defined'
              end
            end

            include Scimitar::Resources::Mixin
          end
        }.to raise_error(RuntimeError, /#{Regexp.escape(required_class_method)}/)
      end
    end
  end # "context 'with bad class definitions' do"

  # ===========================================================================
  # Correct class definitions
  # ===========================================================================

  context 'with good class definitons' do

    require_relative '../../../apps/dummy/app/models/mock_user.rb'

    # =========================================================================
    # Support methods
    # =========================================================================

    context '#scim_queryable_attributes' do
      it 'exposes queryable attributes as an instance method' do
        instance_result = MockUser.new.scim_queryable_attributes()
        class_result    = MockUser.scim_queryable_attributes()

        expect(instance_result).to match_array(class_result)
      end
    end # "context '#scim_queryable_attributes' do"

    context '#scim_mutable_attributes' do
      it 'self-compiles mutable attributes and exposes them as an instance method' do
        readwrite_attrs = MockUser::READWRITE_ATTRS.map(&:to_sym)
        readwrite_attrs.delete(:id) # Should never be offered as writable in SCIM

        result = MockUser.new.scim_mutable_attributes()
        expect(result).to match_array(readwrite_attrs)
      end
    end # "context '#scim_mutable_attributes' do"

    # =========================================================================
    # #to_scim
    # =========================================================================

    context '#to_scim' do
      it 'compiles instance attribute values into a SCIM representation' do
        instance                    = MockUser.new
        instance.id                 = 42
        instance.scim_uid           = 'AA02984'
        instance.username           = 'foo'
        instance.first_name         = 'Foo'
        instance.last_name          = 'Bar'
        instance.work_email_address = 'foo.bar@test.com'
        instance.work_phone_number  = '+642201234567'

        g1 = MockGroup.create!(display_name: 'Group 1')
        g2 = MockGroup.create!(display_name: 'Group 2')
        g3 = MockGroup.create!(display_name: 'Group 3')

        g1.mock_users << instance
        g3.mock_users << instance

        scim = instance.to_scim(location: 'https://test.com/mock_users/42')
        json = scim.to_json()
        hash = JSON.parse(json)

        expect(hash).to eql({
          'userName'    => 'foo',
          'name'        => {'givenName'=>'Foo', 'familyName'=>'Bar'},
          'active'      => true,
          'emails'      => [{'type'=>'work', 'primary'=>true,  'value'=>'foo.bar@test.com'}], # Note, 'type' present
          'phoneNumbers'=> [{'type'=>'work', 'primary'=>false, 'value'=>'+642201234567'   }], # Note, 'type' present
          'id'          => '42', # Note, String
          'externalId'  => 'AA02984',
          'groups'      => [{'display'=>g1.display_name, 'value'=>g1.id.to_s}, {'display'=>g3.display_name, 'value'=>g3.id.to_s}],
          'meta'        => {'location'=>'https://test.com/mock_users/42', 'resourceType'=>'User'},
          'schemas'     => ['urn:ietf:params:scim:schemas:core:2.0:User']
        })
      end

      context 'with optional timestamps' do
        context 'creation only' do
          class CreationOnlyTest < MockUser
            attr_accessor :created_at

            def self.scim_timestamps_map
              { created: :created_at }
            end
          end

          it 'renders the creation date/time' do
            instance            = CreationOnlyTest.new
            instance.created_at = Time.now

            scim = instance.to_scim(location: 'https://test.com/mock_users/42')
            json = scim.to_json()
            hash = JSON.parse(json)

            expect(hash['meta']).to eql({
              'created'      => instance.created_at.iso8601(0),
              'location'     => 'https://test.com/mock_users/42',
              'resourceType' => 'User'
            })
          end
        end # "context 'creation only' do"

        context 'update only' do
          class UpdateOnlyTest < MockUser
            attr_accessor :updated_at

            def self.scim_timestamps_map
              { lastModified: :updated_at }
            end
          end

          it 'renders the modification date/time' do
            instance            = UpdateOnlyTest.new
            instance.updated_at = Time.now

            scim = instance.to_scim(location: 'https://test.com/mock_users/42')
            json = scim.to_json()
            hash = JSON.parse(json)

            expect(hash['meta']).to eql({
              'lastModified' => instance.updated_at.iso8601(0),
              'location'     => 'https://test.com/mock_users/42',
              'resourceType' => 'User'
            })
          end
        end # "context 'update only' do"

        context 'create and update' do
          class CreateAndUpdateTest < MockUser
            attr_accessor :created_at, :updated_at

            def self.scim_timestamps_map
              {
                created:      :created_at,
                lastModified: :updated_at
              }
            end
          end

          it 'renders the creation and modification date/times' do
            instance            = CreateAndUpdateTest.new
            instance.created_at = Time.now - 1.month
            instance.updated_at = Time.now

            scim = instance.to_scim(location: 'https://test.com/mock_users/42')
            json = scim.to_json()
            hash = JSON.parse(json)

            expect(hash['meta']).to eql({
              'created'      => instance.created_at.iso8601(0),
              'lastModified' => instance.updated_at.iso8601(0),
              'location'     => 'https://test.com/mock_users/42',
              'resourceType' => 'User'
            })
          end
        end # "context 'create and update' do"
      end # "context 'with optional timestamps' do"

      context 'with arrays' do
        context 'using static mappings' do
          it 'converts to a SCIM representation' do
            instance = StaticMapTest.new(work_email_address: 'work@test.com', home_email_address: 'home@test.com')
            scim     = instance.to_scim(location: 'https://test.com/static_map_test')
            json     = scim.to_json()
            hash     = JSON.parse(json)

            expect(hash).to eql({
              'emails' => [
                {'type'=>'work', 'primary'=>false, 'value'=>'work@test.com'},
                {'type'=>'home',                   'value'=>'home@test.com'},
              ],

              'meta'    => {'location'=>'https://test.com/static_map_test', 'resourceType'=>'User'},
              'schemas' => ['urn:ietf:params:scim:schemas:core:2.0:User']
            })
          end
        end # "context 'using static mappings' do"

        context 'using dynamic lists' do
          it 'converts to a SCIM representation' do
            group  = Struct.new(:id, :full_name, keyword_init: true)
            groups = [
              group.new(id: 1, full_name: 'Group 1'),
              group.new(id: 2, full_name: 'Group 2'),
              group.new(id: 3, full_name: 'Group 3'),
            ]

            instance = DynamicMapTest.new(groups: groups)
            scim     = instance.to_scim(location: 'https://test.com/dynamic_map_test')
            json     = scim.to_json()
            hash     = JSON.parse(json)

            expect(hash).to eql({
              'groups' => [
                {'display'=>'Group 1', 'value'=>'1'},
                {'display'=>'Group 2', 'value'=>'2'},
                {'display'=>'Group 3', 'value'=>'3'},
              ],

              'meta'    => {'location'=>'https://test.com/dynamic_map_test', 'resourceType'=>'User'},
              'schemas' => ['urn:ietf:params:scim:schemas:core:2.0:User']
            })
          end
        end # "context 'using dynamic lists' do"
      end # "context 'with arrays' do"
    end # "context '#to_scim' do"

    # =========================================================================
    # #from_scim!
    # =========================================================================

    context '#from_scim!' do
      context 'writes instance attribute values from a SCIM representation' do
        it 'ignoring read-only lists' do
          hash = {
            'userName'    => 'foo',
            'name'        => {'givenName'=>'Foo', 'familyName'=>'Bar'},
            'active'      => true,
            'emails'      => [{'type'=>'work', 'primary'=>true,  'value'=>'foo.bar@test.com'}],
            'phoneNumbers'=> [{'type'=>'work', 'primary'=>false, 'value'=>'+642201234567'   }],
            'groups'      => [{'type'=>'Group', 'value'=>'1'}, {'type'=>'Group', 'value'=>'2'}],
            'id'          => '42', # Note, String
            'externalId'  => 'AA02984',
            'meta'        => {'location'=>'https://test.com/mock_users/42', 'resourceType'=>'User'},
            'schemas'     => ['urn:ietf:params:scim:schemas:core:2.0:User']
          }

          instance = MockUser.new
          instance.from_scim!(scim_hash: hash)

          expect(instance.scim_uid          ).to eql('AA02984')
          expect(instance.username          ).to eql('foo')
          expect(instance.first_name        ).to eql('Foo')
          expect(instance.last_name         ).to eql('Bar')
          expect(instance.work_email_address).to eql('foo.bar@test.com')
          expect(instance.work_phone_number ).to eql('+642201234567')
        end

        it 'honouring read-write lists' do
          g1 = MockGroup.create!(display_name: 'Nested group')

          u1 = MockUser.create!(first_name: 'Member 1')
          u2 = MockUser.create!(first_name: 'Member 2')
          u3 = MockUser.create!(first_name: 'Member 3')

          hash = {
            'displayName' => 'Foo Group',
            'members'     => [
              {'type'=>'Group', 'value'=>g1.id.to_s},
              {'type'=>'User',  'value'=>u1.id.to_s},
              {'type'=>'User',  'value'=>u3.id.to_s}
            ],
            'externalId'  => 'GG01536',
            'meta'        => {'location'=>'https://test.com/mock_groups/1', 'resourceType'=>'Group'},
            'schemas'     => ['urn:ietf:params:scim:schemas:core:2.0:Group']
          }

          instance = MockGroup.new
          instance.from_scim!(scim_hash: hash)

          expect(instance.scim_uid         ).to eql('GG01536')
          expect(instance.display_name     ).to eql('Foo Group')
          expect(instance.mock_users       ).to match_array([u1, u3])
          expect(instance.child_mock_groups).to match_array([g1])

          instance.save!
          expect(g1.reload.parent_id).to eql(instance.id)
        end
      end # "context 'writes instance attribute values from a SCIM representation' do"
    end # "context '#from_scim!' do"

    # =========================================================================
    # #from_patch!
    # =========================================================================

    context '#from_patch!' do

      # -------------------------------------------------------------------
      # Internal
      # -------------------------------------------------------------------
      #
      # PATCH is so enormously complex that we do lots of unit tests on private
      # methods before even bothering with the higher level "unit" (more like
      # integration!) tests on #from_patch! itself.
      #
      # These were used during development to debug the implementation.
      #
      context 'internal unit tests' do
        before :each do
          @instance = MockUser.new
        end

        # ---------------------------------------------------------------------
        # Internal: #extract_filter_from
        # ---------------------------------------------------------------------
        #
        context '#extract_filter_from' do
          it 'handles normal path components' do
            path_component, filter = @instance.send(:extract_filter_from, path_component: 'emails')

            expect(path_component).to eql('emails')
            expect(filter        ).to be_nil
          end

          it 'handles path components with filter strings' do
            path_component, filter = @instance.send(:extract_filter_from, path_component: 'addresses[type eq "work"]')

            expect(path_component).to eql('addresses')
            expect(filter        ).to eql('type eq "work"')
          end
        end # "context '#extract_filter_from' do"

        # ---------------------------------------------------------------------
        # Internal: #all_matching_filter
        # ---------------------------------------------------------------------
        #
        context '#all_matching_filter' do
          it 'complains about unsupported operators' do
            expect do
              @instance.send(:all_matching_filter, filter: 'type ne "work"', within_array: []) do
                fail # Block should never be called!
              end
            end.to raise_error(RuntimeError)
          end

          it 'complaints about unsupported multiple operators' do
            expect do
              @instance.send(:all_matching_filter, filter: 'type eq "work" and primary eq true', within_array: []) do
                fail # Block should never be called!
              end
            end.to raise_error(RuntimeError)
          end

          it 'calls block with matches' do
            array = [
              {
                'type'  => 'work',
                'value' => 'work_1@test.com'
              },
              {
                'type'  => 'home',
                'value' => 'home@test.com'
              },
              {
                'type'  => 'work',
                'value' => 'work_2@test.com'
              }
            ]

            unhandled = ['work_1@test.com', 'work_2@test.com']

            @instance.send(:all_matching_filter, filter: 'type eq "work"', within_array: array) do |matched_hash, index|
              expect(array[index]).to eql(matched_hash)

              expect(matched_hash['type']).to eql('work')
              expect(matched_hash).to have_key('value')

              unhandled.delete(matched_hash['value'])
            end

            expect(unhandled).to be_empty
          end

          it 'handles edge cases' do
            array = [
              {
                'type'  => '"work',
                'value' => 'work_leading_dquote@test.com'
              },
              {
                'type'  => true,
                'value' => 'boolean@test.com'
              },
              {
                'type'  => 'work"',
                'value' => 'work_trailing_dquote@test.com'
              }
            ]

            call_count = 0

            @instance.send(:all_matching_filter, filter: 'type eq "work', within_array: array) do |matched_hash, index|
              call_count += 1
              expect(matched_hash['value']).to eql('work_leading_dquote@test.com')
            end

            @instance.send(:all_matching_filter, filter: 'type eq work"', within_array: array) do |matched_hash, index|
              call_count += 1
              expect(matched_hash['value']).to eql('work_trailing_dquote@test.com')
            end

            @instance.send(:all_matching_filter, filter: 'type eq true', within_array: array) do |matched_hash, index|
              call_count += 1
              expect(matched_hash['value']).to eql('boolean@test.com')
            end

            expect(call_count).to eql(3)
          end
        end # "context '#all_matching_filter' do"

        # ---------------------------------------------------------------------
        # Internal: #from_patch_backend
        # ---------------------------------------------------------------------
        #
        context '#from_patch_backend!' do

          # -------------------------------------------------------------------
          # Internal: #from_patch_backend - add
          # -------------------------------------------------------------------
          #
          # Except for filter and array behaviour at the leaf of the path,
          # "add" and "replace" are pretty much identical.
          #
          context 'add' do
            context 'when prior value already exists' do
              it 'simple value: overwrites' do
                path      = [ 'userName' ]
                scim_hash = { 'userName' => 'bar' }

                @instance.send(
                  :from_patch_backend!,
                  nature:        'add',
                  path:          path,
                  value:         'foo',
                  altering_data: scim_hash
                )

                expect(scim_hash['userName']).to eql('foo')
              end

              it 'nested simple value: overwrites' do
                path      = [ 'name', 'givenName' ]
                scim_hash = { 'name' => { 'givenName' => 'Foo', 'familyName' => 'Bar' } }

                @instance.send(
                  :from_patch_backend!,
                  nature:        'add',
                  path:          path,
                  value:         'Baz',
                  altering_data: scim_hash
                )

                expect(scim_hash['name']['givenName' ]).to eql('Baz')
                expect(scim_hash['name']['familyName']).to eql('Bar')
              end

              # For 'add', filter at end-of-path is nonsensical and not
              # supported by spec or Scimitar; we only test mid-path filters.
              #
              context 'with filter mid-path' do
                it 'by string match: overwrites' do
                  path      = [ 'emails[type eq "work"]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'home',
                        'value' => 'home@test.com'
                      },
                      {
                        'type' => 'work',
                        'value' => 'work@test.com'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'add',
                    path:          path,
                    value:         'added_over_origina@test.com',
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                  expect(scim_hash['emails'][1]['value']).to eql('added_over_origina@test.com')
                end

                it 'by boolean match: overwrites' do
                  path      = [ 'emails[primary eq true]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'value' => 'home@test.com'
                      },
                      {
                        'value' => 'work@test.com',
                        'primary' => true
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'add',
                    path:          path,
                    value:         'added_over_origina@test.com',
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                  expect(scim_hash['emails'][1]['value']).to eql('added_over_origina@test.com')
                end

                it 'multiple matches: overwrites all' do
                  path      = [ 'emails[type eq "work"]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'work',
                        'value' => 'work_1@test.com'
                      },
                      {
                        'type' => 'work',
                        'value' => 'work_2@test.com'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'add',
                    path:          path,
                    value:         'added_over_origina@test.com',
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('added_over_origina@test.com')
                  expect(scim_hash['emails'][1]['value']).to eql('added_over_origina@test.com')
                end
              end # "context 'with filter mid-path' do"

              it 'with arrays: appends' do
                path      = [ 'emails' ]
                scim_hash = {
                  'emails' => [
                    {
                      'type' => 'home',
                      'value' => 'home@test.com'
                    }
                  ]
                }

                @instance.send(
                  :from_patch_backend!,
                  nature:        'add',
                  path:          path,
                  value:         [ { 'type' => 'work', 'value' => 'work@test.com' } ], # NOTE - to-add value is an Array (and must be)
                  altering_data: scim_hash
                )

                expect(scim_hash['emails'].size).to eql(2)
                expect(scim_hash['emails'][1]['type' ]).to eql('work')
                expect(scim_hash['emails'][1]['value']).to eql('work@test.com')
              end
            end # context 'when prior value already exists' do

            context 'when value is not present' do
              it 'simple value: adds' do
                path      = [ 'userName' ]
                scim_hash = {}

                @instance.send(
                  :from_patch_backend!,
                  nature:        'add',
                  path:          path,
                  value:         'foo',
                  altering_data: scim_hash
                )

                expect(scim_hash['userName']).to eql('foo')
              end

              it 'nested simple value: adds' do
                path      = [ 'name', 'givenName' ]
                scim_hash = {}

                @instance.send(
                  :from_patch_backend!,
                  nature:        'add',
                  path:          path,
                  value:         'Baz',
                  altering_data: scim_hash
                )

                expect(scim_hash['name']['givenName']).to eql('Baz')
              end

              context 'with filter mid-path: adds' do
                it 'by string match' do
                  path      = [ 'emails[type eq "work"]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'home',
                        'value' => 'home@test.com'
                      },
                      {
                        'type' => 'work'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'add',
                    path:          path,
                    value:         'added@test.com',
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                  expect(scim_hash['emails'][1]['value']).to eql('added@test.com')
                end

                it 'by boolean match: adds' do
                  path      = [ 'emails[primary eq true]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'value' => 'home@test.com'
                      },
                      {
                        'primary' => true
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'add',
                    path:          path,
                    value:         'added@test.com',
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                  expect(scim_hash['emails'][1]['value']).to eql('added@test.com')
                end

                it 'multiple matches: adds to all' do
                  path      = [ 'emails[type eq "work"]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'work'
                      },
                      {
                        'type' => 'work'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'add',
                    path:          path,
                    value:         'added@test.com',
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('added@test.com')
                  expect(scim_hash['emails'][1]['value']).to eql('added@test.com')
                end
              end # "context 'with filter mid-path' do"

              it 'with arrays: appends' do
                path      = [ 'emails' ]
                scim_hash = {}

                @instance.send(
                  :from_patch_backend!,
                  nature:        'add',
                  path:          path,
                  value:         [ { 'type' => 'work', 'value' => 'work@test.com' } ], # NOTE - to-add value is an Array (and must be)
                  altering_data: scim_hash
                )

                expect(scim_hash['emails'].size).to eql(1)
                expect(scim_hash['emails'][0]['type' ]).to eql('work')
                expect(scim_hash['emails'][0]['value']).to eql('work@test.com')
              end
            end # context 'when value is not present' do
          end # "context 'add' do"

          # -------------------------------------------------------------------
          # Internal: #from_patch_backend - remove
          # -------------------------------------------------------------------
          #
          context 'remove' do
            context 'when prior value already exists' do
              it 'simple value: removes' do
                path      = [ 'userName' ]
                scim_hash = { 'userName' => 'bar' }

                @instance.send(
                  :from_patch_backend!,
                  nature:        'remove',
                  path:          path,
                  value:         nil,
                  altering_data: scim_hash
                )

                expect(scim_hash).to be_empty
              end

              it 'nested simple value: removes' do
                path      = [ 'name', 'givenName' ]
                scim_hash = { 'name' => { 'givenName' => 'Foo', 'familyName' => 'Bar' } }

                @instance.send(
                  :from_patch_backend!,
                  nature:        'remove',
                  path:          path,
                  value:         nil,
                  altering_data: scim_hash
                )

                expect(scim_hash['name']).to_not have_key('givenName')
                expect(scim_hash['name']['familyName']).to eql('Bar')
              end

              context 'with filter mid-path' do
                it 'by string match: removes' do
                  path      = [ 'emails[type eq "work"]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'home',
                        'value' => 'home@test.com'
                      },
                      {
                        'type' => 'work',
                        'value' => 'work@test.com'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'remove',
                    path:          path,
                    value:         nil,
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                  expect(scim_hash['emails'][1]).to_not have_key('value')
                end

                it 'by boolean match: removes' do
                  path      = [ 'emails[primary eq true]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'value' => 'home@test.com'
                      },
                      {
                        'value' => 'work@test.com',
                        'primary' => true
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'remove',
                    path:          path,
                    value:         nil,
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                  expect(scim_hash['emails'][1]).to_not have_key('value')
                end

                it 'multiple matches: removes all' do
                  path      = [ 'emails[type eq "work"]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'work',
                        'value' => 'work_1@test.com'
                      },
                      {
                        'type' => 'work',
                        'value' => 'work_2@test.com'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'remove',
                    path:          path,
                    value:         nil,
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]).to_not have_key('value')
                  expect(scim_hash['emails'][1]).to_not have_key('value')
                end
              end # "context 'with filter mid-path' do"

              context 'with filter at end of path' do
                it 'by string match: removes entire matching array entry' do
                  path      = [ 'emails[type eq "work"]' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'home',
                        'value' => 'home@test.com'
                      },
                      {
                        'type' => 'work',
                        'value' => 'work@test.com'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'remove',
                    path:          path,
                    value:         nil,
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'].size).to eql(1)
                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                end

                it 'by boolean match: removes entire matching array entry' do
                  path      = [ 'emails[primary eq true]' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'value' => 'home@test.com'
                      },
                      {
                        'value' => 'work@test.com',
                        'primary' => true
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'remove',
                    path:          path,
                    value:         nil,
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'].size).to eql(1)
                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                end

                it 'multiple matches: removes all matching array entries' do
                  path      = [ 'emails[type eq "work"]' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'work',
                        'value' => 'work_1@test.com'
                      },
                      {
                        'type' => 'work',
                        'value' => 'work_2@test.com'
                      },
                      {
                        'type' => 'home',
                        'value' => 'home@test.com'
                      },
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'remove',
                    path:          path,
                    value:         nil,
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'].size).to eql(1)
                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                end
              end # "context 'with filter at end of path' do"

              it 'whole array: removes' do
                path      = [ 'emails' ]
                scim_hash = {
                  'emails' => [
                    {
                      'type' => 'home',
                      'value' => 'home@test.com'
                    }
                  ]
                }

                @instance.send(
                  :from_patch_backend!,
                  nature:        'remove',
                  path:          path,
                  value:         nil,
                  altering_data: scim_hash
                )

                expect(scim_hash).to_not have_key('emails')
              end
            end # context 'when prior value already exists' do

            context 'when value is not present' do
              it 'simple value: does nothing' do
                path      = [ 'userName' ]
                scim_hash = {}

                @instance.send(
                  :from_patch_backend!,
                  nature:        'remove',
                  path:          path,
                  value:         nil,
                  altering_data: scim_hash
                )

                expect(scim_hash).to be_empty
              end

              it 'nested simple value: does nothing' do
                path      = [ 'name', 'givenName' ]
                scim_hash = { 'name' => {'familyName' => 'Bar' } }

                @instance.send(
                  :from_patch_backend!,
                  nature:        'remove',
                  path:          path,
                  value:         nil,
                  altering_data: scim_hash
                )

                expect(scim_hash['name']).to_not have_key('givenName')
                expect(scim_hash['name']['familyName']).to eql('Bar')
              end

              context 'with filter mid-path' do
                it 'by string match: does nothing' do
                  path      = [ 'emails[type eq "work"]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'home',
                        'value' => 'home@test.com'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'remove',
                    path:          path,
                    value:         nil,
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'].size).to eql(1)
                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                end

                it 'by boolean match: does nothing' do
                  path      = [ 'emails[primary eq true]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'value' => 'home@test.com'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'remove',
                    path:          path,
                    value:         nil,
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'].size).to eql(1)
                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                end

                it 'multiple matches: does nothing' do
                  path      = [ 'emails[type eq "work"]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'home',
                        'value' => 'home@test.com'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'remove',
                    path:          path,
                    value:         nil,
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'].size).to eql(1)
                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                end
              end # "context 'with filter mid-path' do"

              context 'with filter at end of path' do
                it 'by string match: does nothing' do
                  path      = [ 'emails[type eq "work"]' ]
                  scim_hash = {}

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'remove',
                    path:          path,
                    value:         nil,
                    altering_data: scim_hash
                  )

                  expect(scim_hash).to be_empty
                end

                it 'by boolean match: does nothing' do
                  path      = [ 'emails[primary eq true]' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'value' => 'home@test.com',
                        'primary' => false
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'remove',
                    path:          path,
                    value:         nil,
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'].size).to eql(1)
                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                end
              end # "context 'with filter at end of path' do"

              it 'remove whole array: does nothing' do
                path      = [ 'emails' ]
                scim_hash = {}

                @instance.send(
                  :from_patch_backend!,
                  nature:        'remove',
                  path:          path,
                  value:         nil,
                  altering_data: scim_hash
                )

                expect(scim_hash).to_not have_key('emails')
              end
            end # context 'when value is not present' do
          end # "context 'remove' do"

          # -------------------------------------------------------------------
          # Internal: #from_patch_backend - replace
          # -------------------------------------------------------------------
          #
          # Except for filter and array behaviour at the leaf of the path,
          # "add" and "replace" are pretty much identical.
          #
          context 'replace' do
            context 'when prior value already exists' do
              it 'simple value: overwrites' do
                path      = [ 'userName' ]
                scim_hash = { 'userName' => 'bar' }

                @instance.send(
                  :from_patch_backend!,
                  nature:        'replace',
                  path:          path,
                  value:         'foo',
                  altering_data: scim_hash
                )

                expect(scim_hash['userName']).to eql('foo')
              end

              it 'nested simple value: overwrites' do
                path      = [ 'name', 'givenName' ]
                scim_hash = { 'name' => { 'givenName' => 'Foo', 'familyName' => 'Bar' } }

                @instance.send(
                  :from_patch_backend!,
                  nature:        'replace',
                  path:          path,
                  value:         'Baz',
                  altering_data: scim_hash
                )

                expect(scim_hash['name']['givenName' ]).to eql('Baz')
                expect(scim_hash['name']['familyName']).to eql('Bar')
              end

              # For 'replace', filter at end-of-path is nonsensical and not
              # supported by spec or Scimitar; we only test mid-path filters.
              #
              context 'with filter mid-path' do
                it 'by string match: overwrites' do
                  path      = [ 'emails[type eq "work"]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'home',
                        'value' => 'home@test.com'
                      },
                      {
                        'type' => 'work',
                        'value' => 'work@test.com'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'replace',
                    path:          path,
                    value:         'added_over_origina@test.com',
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                  expect(scim_hash['emails'][1]['value']).to eql('added_over_origina@test.com')
                end

                it 'by boolean match: overwrites' do
                  path      = [ 'emails[primary eq true]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'value' => 'home@test.com'
                      },
                      {
                        'value' => 'work@test.com',
                        'primary' => true
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'replace',
                    path:          path,
                    value:         'added_over_origina@test.com',
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                  expect(scim_hash['emails'][1]['value']).to eql('added_over_origina@test.com')
                end

                it 'multiple matches: overwrites all' do
                  path      = [ 'emails[type eq "work"]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'work',
                        'value' => 'work_1@test.com'
                      },
                      {
                        'type' => 'work',
                        'value' => 'work_2@test.com'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'replace',
                    path:          path,
                    value:         'added_over_origina@test.com',
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('added_over_origina@test.com')
                  expect(scim_hash['emails'][1]['value']).to eql('added_over_origina@test.com')
                end
              end # "context 'with filter mid-path' do"

              it 'with arrays: replaces whole array' do
                path      = [ 'emails' ]
                scim_hash = {
                  'emails' => [
                    {
                      'type' => 'home',
                      'value' => 'home@test.com'
                    }
                  ]
                }

                @instance.send(
                  :from_patch_backend!,
                  nature:        'replace',
                  path:          path,
                  value:         [ { 'type' => 'work', 'value' => 'work@test.com' } ], # NOTE - to-add value is an Array (and must be)
                  altering_data: scim_hash
                )

                expect(scim_hash['emails'].size).to eql(1)
                expect(scim_hash['emails'][0]['type' ]).to eql('work')
                expect(scim_hash['emails'][0]['value']).to eql('work@test.com')
              end
            end # context 'when prior value already exists' do

            context 'when value is not present' do
              it 'simple value: adds' do
                path      = [ 'userName' ]
                scim_hash = {}

                @instance.send(
                  :from_patch_backend!,
                  nature:        'replace',
                  path:          path,
                  value:         'foo',
                  altering_data: scim_hash
                )

                expect(scim_hash['userName']).to eql('foo')
              end

              it 'nested simple value: adds' do
                path      = [ 'name', 'givenName' ]
                scim_hash = {}

                @instance.send(
                  :from_patch_backend!,
                  nature:        'replace',
                  path:          path,
                  value:         'Baz',
                  altering_data: scim_hash
                )

                expect(scim_hash['name']['givenName']).to eql('Baz')
              end

              context 'with filter mid-path: adds' do
                it 'by string match' do
                  path      = [ 'emails[type eq "work"]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'home',
                        'value' => 'home@test.com'
                      },
                      {
                        'type' => 'work'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'replace',
                    path:          path,
                    value:         'added@test.com',
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                  expect(scim_hash['emails'][1]['value']).to eql('added@test.com')
                end

                it 'by boolean match: adds' do
                  path      = [ 'emails[primary eq true]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'value' => 'home@test.com'
                      },
                      {
                        'primary' => true
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'replace',
                    path:          path,
                    value:         'added@test.com',
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('home@test.com')
                  expect(scim_hash['emails'][1]['value']).to eql('added@test.com')
                end

                it 'multiple matches: adds to all' do
                  path      = [ 'emails[type eq "work"]', 'value' ]
                  scim_hash = {
                    'emails' => [
                      {
                        'type' => 'work'
                      },
                      {
                        'type' => 'work'
                      }
                    ]
                  }

                  @instance.send(
                    :from_patch_backend!,
                    nature:        'replace',
                    path:          path,
                    value:         'added@test.com',
                    altering_data: scim_hash
                  )

                  expect(scim_hash['emails'][0]['value']).to eql('added@test.com')
                  expect(scim_hash['emails'][1]['value']).to eql('added@test.com')
                end
              end # "context 'with filter mid-path' do"

              it 'with arrays: replaces' do
                path      = [ 'emails' ]
                scim_hash = {}

                @instance.send(
                  :from_patch_backend!,
                  nature:        'replace',
                  path:          path,
                  value:         [ { 'type' => 'work', 'value' => 'work@test.com' } ], # NOTE - to-add value is an Array (and must be)
                  altering_data: scim_hash
                )

                expect(scim_hash['emails'].size).to eql(1)
                expect(scim_hash['emails'][0]['type' ]).to eql('work')
                expect(scim_hash['emails'][0]['value']).to eql('work@test.com')
              end
            end # context 'when value is not present' do
          end # "context 'replace' do"

          context 'with bad patches, raises errors' do
            it 'for unsupported filters' do
              path      = [ 'emails[type ne "work" and value ne "hello@test.com"', 'value' ]
              scim_hash = {
                'emails' => [
                  {
                    'type' => 'work',
                    'value' => 'work_1@test.com'
                  },
                  {
                    'type' => 'work',
                    'value' => 'work_2@test.com'
                  }
                ]
              }

              expect do
                @instance.send(
                  :from_patch_backend!,
                  nature:        'replace',
                  path:          path,
                  value:         'ignored',
                  altering_data: scim_hash
                )
              end.to raise_error(Scimitar::ErrorResponse)
            end

            it 'when filters are specified for non-array types' do
              path      = [ 'userName[type eq "work"]', 'value' ]
              scim_hash = {
                'userName' => '1234'
              }

              expect do
                @instance.send(
                  :from_patch_backend!,
                  nature:        'replace',
                  path:          path,
                  value:         'ignored',
                  altering_data: scim_hash
                )
              end.to raise_error(Scimitar::ErrorResponse)
            end

            it 'when a filter tries to match an array which does not contain Hashes' do
              path      = [ 'emails[type eq "work"]', 'value' ]
              scim_hash = {
                'emails' => [
                  'work_1@test.com',
                  'work_2@test.com',
                ]
              }

              expect do
                @instance.send(
                  :from_patch_backend!,
                  nature:        'replace',
                  path:          path,
                  value:         'ignored',
                  altering_data: scim_hash
                )
              end.to raise_error(Scimitar::ErrorResponse)
            end
          end # context 'with bad patches, raises errors' do
        end # "context '#from_patch_backend!' do"
      end # "context 'internal unit tests' do"

      # -------------------------------------------------------------------
      # Public
      # -------------------------------------------------------------------
      #
      xcontext 'public interface' do
        it 'hopefully works' do
        end
      end # "context 'public interface' do"
    end # "context '#from_patch!' do"
  end # "context 'with good class definitons' do"
end # "RSpec.describe Scimitar::Resources::Mixin do"