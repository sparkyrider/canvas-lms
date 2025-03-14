# frozen_string_literal: true

#
# Copyright (C) 2011 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

describe MediaObjectsController do
  before :once do
    course_with_teacher(active_all: true)
    student_in_course(active_all: true)
  end

  before do
    stub_kaltura
  end

  describe "GET 'show'" do
    before do
      # We don't actually want to ping kaltura during these tests
      allow(MediaObject).to receive(:media_id_exists?).and_return(true)
      allow_any_instance_of(MediaObject).to receive(:media_sources).and_return(
        [{ url: "whatever man", bitrate: 12_345 }]
      )
    end

    it "creates a MediaObject if necessary on request" do
      # this test is purposely run with no user logged in to make sure it works in public courses
      allow_any_instance_of(MediaObject).to receive(:context).and_return(course_factory)

      missing_media_id = "0_12345678"
      expect(MediaObject.by_media_id(missing_media_id)).to be_empty

      get "show", params: { media_object_id: missing_media_id }
      expect(json_parse(response.body)).to include(
        {
          "can_add_captions" => false,
          "media_id" => missing_media_id,
          "title" => "Untitled",
          "media_type" => nil,
          "media_tracks" => [],
          "media_sources" => [
            {
              "bitrate" => 12_345,
              "label" => "12 kbps",
              "src" => "whatever man",
              "url" => "whatever man"
            }
          ]
        }
      )
      expect(MediaObject.by_media_id(missing_media_id).first.media_id).to eq missing_media_id
    end

    it "retrieves info about a 'deleted' MediaObject" do
      deleted_media_id = "0_deadbeef"
      course_factory
      media_object = course_factory.media_objects.build media_id: deleted_media_id
      media_object.workflow_state = "deleted"
      media_object.save!

      get "show", params: { media_object_id: deleted_media_id }
      expect(json_parse(response.body)).to eq(
        {
          "can_add_captions" => false,
          "created_at" => media_object.created_at.as_json,
          "media_id" => deleted_media_id,
          "title" => "Untitled",
          "media_type" => nil,
          "media_tracks" => [],
          "media_sources" => [
            {
              "bitrate" => 12_345,
              "label" => "12 kbps",
              "src" => "whatever man",
              "url" => "whatever man"
            }
          ],
          "embedded_iframe_url" => "http://test.host/media_objects_iframe/#{deleted_media_id}"
        }
      )
    end

    context "adheres to attachment permissions" do
      before :once do
        attachment_model(context: @course)
      end

      it "allows students access to MediaObject through attachment" do
        user_session(@student)
        @attachment.update(content_type: "video", media_entry_id: "maybe")

        expect(@attachment.grants_right?(@student, :read)).to be(true)

        MediaObject.create!(user_id: @teacher, media_id: "maybe")
        get "show", params: { attachment_id: @attachment.id }
        assert_status(200)
      end

      it "disallows access for unauthorized user" do
        user_model
        user_session(@user)
        @attachment.update(content_type: "video", media_entry_id: "maybe")

        expect(@attachment.grants_right?(@user, :read)).to be(false)

        MediaObject.create!(user_id: @teacher, media_id: "maybe")
        get "show", params: { attachment_id: @attachment.id }
        assert_status(401)
      end
    end
  end

  describe "GET 'index'" do
    before do
      # We don't actually want to ping kaltura during these tests
      allow(MediaObject).to receive(:media_id_exists?).and_return(true)
      allow_any_instance_of(MediaObject).to receive(:media_sources).and_return(
        [{ url: "whatever man", bitrate: 12_345 }]
      )
    end

    it "retrieves all MediaObjects user in the user's context" do
      user_factory
      user_session(@user)
      mo1 =
        MediaObject.create!(user_id: @user, context: @user, media_id: "test", media_type: "video")
      mo2 =
        MediaObject.create!(
          user_id: @user, context: @user, media_id: "test2", media_type: "audio", title: "The Title"
        )
      mo3 =
        MediaObject.create!(
          user_id: @user, context: @user, media_id: "test3", user_entered_title: "User Title"
        )

      get "index"
      expect(json_parse(response.body)).to match_array(
        [
          {
            "can_add_captions" => true,
            "created_at" => mo2.created_at.as_json,
            "media_id" => "test2",
            "media_sources" => [
              {
                "bitrate" => 12_345,
                "label" => "12 kbps",
                "src" => "whatever man",
                "url" => "whatever man"
              }
            ],
            "media_tracks" => [],
            "title" => "The Title",
            "media_type" => "audio",
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test2"
          },
          {
            "can_add_captions" => true,
            "created_at" => mo3.created_at.as_json,
            "media_id" => "test3",
            "media_sources" => [
              {
                "bitrate" => 12_345,
                "label" => "12 kbps",
                "src" => "whatever man",
                "url" => "whatever man"
              }
            ],
            "media_tracks" => [],
            "title" => "User Title",
            "media_type" => nil,
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test3"
          },
          {
            "can_add_captions" => true,
            "created_at" => mo1.created_at.as_json,
            "media_id" => "test",
            "media_sources" => [
              {
                "bitrate" => 12_345,
                "label" => "12 kbps",
                "src" => "whatever man",
                "url" => "whatever man"
              }
            ],
            "media_tracks" => [],
            "title" => "Untitled",
            "media_type" => "video",
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test"
          }
        ]
      )
    end

    it "will not retrive items you did not create" do
      user1 = user_factory
      user2 = user_factory
      user_session(user1)
      MediaObject.create!(user_id: user2, context: user2, media_id: "test")
      MediaObject.create!(user_id: user2, context: user2, media_id: "test2")
      MediaObject.create!(user_id: user2, context: user2, media_id: "test3")

      get "index"
      expect(json_parse(response.body)).to eq([])
    end

    it "will exclude media_sources if asked to" do
      user_factory
      user_session(@user)
      mo =
        MediaObject.create!(user_id: @user, context: @user, media_id: "test", media_type: "video")

      get "index", params: { exclude: %w[sources] }
      expect(json_parse(response.body)).to eq(
        [
          {
            "can_add_captions" => true,
            "created_at" => mo.created_at.as_json,
            "media_id" => "test",
            "media_tracks" => [],
            "title" => "Untitled",
            "media_type" => "video",
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test"
          }
        ]
      )
    end

    it "will exclude media_tracks if asked to" do
      user_factory
      user_session(@user)
      mo =
        MediaObject.create!(user_id: @user, context: @user, media_id: "test", media_type: "video")

      get "index", params: { exclude: %w[tracks] }
      expect(json_parse(response.body)).to eq(
        [
          {
            "can_add_captions" => true,
            "created_at" => mo.created_at.as_json,
            "media_id" => "test",
            "media_sources" => [
              {
                "bitrate" => 12_345,
                "label" => "12 kbps",
                "src" => "whatever man",
                "url" => "whatever man"
              }
            ],
            "title" => "Untitled",
            "media_type" => "video",
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test"
          }
        ]
      )
    end

    it "will return media objects that do not belong to the user if course_id is supplied" do
      course_factory
      teacher1 = teacher_in_course(course: @course).user
      teacher2 = teacher_in_course(course: @course).user

      user_session(teacher1)

      # a media object associated with a canvas attachment
      mo1 = MediaObject.create!(user_id: teacher2, context: @course, media_id: "test")
      @course.attachments.create!(media_entry_id: "test", uploaded_data: stub_png_data)
      # and a media object that's not
      mo2 = MediaObject.create!(user_id: teacher2, context: @course, media_id: "another_test")

      get "index", params: { course_id: @course.id, exclude: %w[sources tracks] }

      expect(json_parse(response.body)).to match_array(
        [
          {
            "can_add_captions" => true,
            "created_at" => mo1.created_at.as_json,
            "media_id" => "test",
            "title" => "Untitled",
            "media_type" => nil,
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test"
          },
          {
            "can_add_captions" => true,
            "created_at" => mo2.created_at.as_json,
            "media_id" => "another_test",
            "title" => "Untitled",
            "media_type" => nil,
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/another_test"
          }
        ]
      )
    end

    it "will paginate user media" do
      user_factory
      user_session(@user)
      mo1 = mo2 = mo3 = nil
      Timecop.freeze(30.seconds.ago) do
        mo1 =
          MediaObject.create!(user_id: @user, context: @user, media_id: "test", media_type: "video")
      end
      Timecop.freeze(20.seconds.ago) do
        mo2 =
          MediaObject.create!(
            user_id: @user,
            context: @user,
            media_id: "test2",
            media_type: "audio",
            title: "The Title"
          )
      end
      Timecop.freeze(10.seconds.ago) do
        mo3 =
          MediaObject.create!(
            user_id: @user, context: @user, media_id: "test3", user_entered_title: "User Title"
          )
      end

      get "index", params: { per_page: 2, order_by: "created_at", order_dir: "desc" }
      expect(json_parse(response.body)).to match_array(
        [
          {
            "can_add_captions" => true,
            "created_at" => mo3.created_at.as_json,
            "media_id" => "test3",
            "media_sources" => [
              {
                "bitrate" => 12_345,
                "label" => "12 kbps",
                "src" => "whatever man",
                "url" => "whatever man"
              }
            ],
            "media_tracks" => [],
            "title" => "User Title",
            "media_type" => nil,
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test3"
          },
          {
            "can_add_captions" => true,
            "created_at" => mo2.created_at.as_json,
            "media_id" => "test2",
            "media_sources" => [
              {
                "bitrate" => 12_345,
                "label" => "12 kbps",
                "src" => "whatever man",
                "url" => "whatever man"
              }
            ],
            "media_tracks" => [],
            "title" => "The Title",
            "media_type" => "audio",
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test2"
          }
        ]
      )

      get "index", params: { per_page: 2, order_by: "created_at", order_dir: "desc", page: 2 }
      expect(json_parse(response.body)).to match_array(
        [
          {
            "can_add_captions" => true,
            "created_at" => mo1.created_at.as_json,
            "media_id" => "test",
            "media_sources" => [
              {
                "bitrate" => 12_345,
                "label" => "12 kbps",
                "src" => "whatever man",
                "url" => "whatever man"
              }
            ],
            "media_tracks" => [],
            "title" => "Untitled",
            "media_type" => "video",
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test"
          }
        ]
      )
    end

    it "will limit return to course media" do
      course_with_teacher_logged_in
      mo1 = MediaObject.create!(user_id: @user, context: @course, media_id: "in_course_with_att")
      @course.attachments.create!(
        media_entry_id: "in_course_with_att", uploaded_data: stub_png_data
      )

      # That media objects associated with a deleted attachment are still returned
      # is an artifact of changes made a long time ago so that Attachments from
      # course copy share the media object.
      # see commit d27cf9f7d037571b2ee88c61be2ca72f19777b60
      mo2 =
        MediaObject.create!(
          user_id: @user, context: @course, media_id: "in_course_with_deleted_att"
        )
      deleted_att =
        @course.attachments.create!(
          media_entry_id: "in_course_with_deleted_att", uploaded_data: stub_png_data
        )
      mo2.attachment_id = deleted_att.id # this normally happens via a delayed_job
      mo2.save!
      deleted_att.destroy!

      MediaObject.create!(user_id: @user, context: @user, media_id: "not_in_course")

      get "index", params: { course_id: @course.id, exclude: %w[sources tracks] }

      expect(json_parse(response.body)).to match_array(
        [
          {
            "media_id" => "in_course_with_att",
            "media_type" => nil,
            "created_at" => mo1.created_at.as_json,
            "title" => "Untitled",
            "can_add_captions" => true,
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/in_course_with_att"
          },
          {
            "media_id" => "in_course_with_deleted_att",
            "media_type" => nil,
            "created_at" => mo2.created_at.as_json,
            "title" => "Untitled",
            "can_add_captions" => true,
            "embedded_iframe_url" =>
              "http://test.host/media_objects_iframe/in_course_with_deleted_att"
          }
        ]
      )
    end

    it "will paginate course media" do
      course_with_teacher_logged_in
      mo1 = mo2 = mo3 = nil
      Timecop.freeze(30.seconds.ago) do
        mo1 =
          MediaObject.create!(
            user_id: @user, context: @course, media_id: "test", media_type: "video"
          )
      end
      Timecop.freeze(20.seconds.ago) do
        mo2 =
          MediaObject.create!(
            user_id: @user,
            context: @course,
            media_id: "test2",
            media_type: "audio",
            title: "The Title"
          )
      end
      Timecop.freeze(10.seconds.ago) do
        mo3 =
          MediaObject.create!(
            user_id: @user, context: @course, media_id: "test3", user_entered_title: "User Title"
          )
      end

      get "index",
          params: { course_id: @course.id, per_page: 2, order_by: "created_at", order_dir: "desc" }
      expect(json_parse(response.body)).to match_array(
        [
          {
            "can_add_captions" => true,
            "created_at" => mo3.created_at.as_json,
            "media_id" => "test3",
            "media_sources" => [
              {
                "bitrate" => 12_345,
                "label" => "12 kbps",
                "src" => "whatever man",
                "url" => "whatever man"
              }
            ],
            "media_tracks" => [],
            "title" => "User Title",
            "media_type" => nil,
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test3"
          },
          {
            "can_add_captions" => true,
            "created_at" => mo2.created_at.as_json,
            "media_id" => "test2",
            "media_sources" => [
              {
                "bitrate" => 12_345,
                "label" => "12 kbps",
                "src" => "whatever man",
                "url" => "whatever man"
              }
            ],
            "media_tracks" => [],
            "title" => "The Title",
            "media_type" => "audio",
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test2"
          }
        ]
      )

      get "index",
          params: {
            course_id: @course.id, per_page: 2, order_by: "created_at", order_dir: "desc", page: 2
          }
      expect(json_parse(response.body)).to match_array(
        [
          {
            "can_add_captions" => true,
            "created_at" => mo1.created_at.as_json,
            "media_id" => "test",
            "media_sources" => [
              {
                "bitrate" => 12_345,
                "label" => "12 kbps",
                "src" => "whatever man",
                "url" => "whatever man"
              }
            ],
            "media_tracks" => [],
            "title" => "Untitled",
            "media_type" => "video",
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test"
          }
        ]
      )
    end

    it "will return a 404 if the given course_id doesn't exist" do
      course_with_teacher_logged_in
      MediaObject.create!(user_id: @user, context: @course, media_id: "in_course")
      MediaObject.create!(user_id: @user, media_id: "not_in_course")

      get "index", params: { course_id: 171_717, exclude: %w[sources tracks] }

      expect(response.status.to_s).to eq("404")
    end

    it "will return user's media if context_type isn't 'course'" do
      course_with_teacher_logged_in
      MediaObject.create!(
        user_id: @user, context: @course, media_id: "in_course", user_entered_title: "AAA"
      )
      mo2 =
        MediaObject.create!(
          user_id: @user, context: @user, media_id: "not_in_course", user_entered_title: "BBB"
        )

      get "index", params: { exclude: %w[sources tracks] }

      expect(json_parse(response.body)).to eq(
        [
          {
            "can_add_captions" => true,
            "created_at" => mo2.created_at.as_json,
            "media_id" => "not_in_course",
            "title" => "BBB",
            "media_type" => nil,
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/not_in_course"
          }
        ]
      )
    end

    it "will limit return to group media" do
      course_with_teacher_logged_in(active_all: true)
      gcat = @course.group_categories.create!(name: "My Group Category")
      @group = Group.create!(name: "some group", group_category: gcat, context: @course)
      mo1 = MediaObject.create!(user_id: @user, context: @group, media_id: "in_group")

      MediaObject.create!(user_id: @user, context: @course, media_id: "in_course_with_att")
      @course.attachments.create!(
        media_entry_id: "in_course_with_att", uploaded_data: stub_png_data
      )

      MediaObject.create!(user_id: @user, context: @user, media_id: "not_in_course")

      get "index", params: { group_id: @group.id, exclude: %w[sources tracks] }

      expect(json_parse(response.body)).to match_array(
        [
          {
            "media_id" => "in_group",
            "media_type" => nil,
            "created_at" => mo1.created_at.as_json,
            "title" => "Untitled",
            "can_add_captions" => true,
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/in_group"
          }
        ]
      )
    end

    it "will sort by title" do
      course_with_teacher_logged_in
      MediaObject.create!(user_id: @user, context: @user, media_id: "test", title: "ZZZ")
      MediaObject.create!(user_id: @user, context: @user, media_id: "test2", title: "YYY")
      MediaObject.create!(user_id: @user, context: @user, media_id: "test3", title: "XXX")

      get "index", params: { exclude: %w[sources tracks], sort: "title", order: "asc" }

      result = json_parse(response.body)
      expect(result[0]["title"]).to eq("XXX")
      expect(result[1]["title"]).to eq("YYY")
      expect(result[2]["title"]).to eq("ZZZ")
    end

    it "will sort by created_at" do
      course_with_teacher_logged_in
      Timecop.freeze(2.seconds.ago) do
        MediaObject.create!(user_id: @user, context: @user, media_id: "test", title: "AAA")
      end
      Timecop.freeze(1.second.ago) do
        MediaObject.create!(user_id: @user, context: @user, media_id: "test2", title: "BBB")
      end
      MediaObject.create!(user_id: @user, context: @user, media_id: "test3", title: "CCC")

      get "index", params: { exclude: %w[sources tracks], sort: "created_at", order: "desc" }

      result = json_parse(response.body)
      expect(result[0]["title"]).to eq("CCC")
      expect(result[1]["title"]).to eq("BBB")
      expect(result[2]["title"]).to eq("AAA")
    end

    it "will search by title" do
      course_with_teacher_logged_in
      MediaObject.create!(user_id: @user, context: @user, media_id: "test", title: "ZZZZ")
      MediaObject.create!(user_id: @user, context: @user, media_id: "test2", title: "YYYY")
      MediaObject.create!(user_id: @user, context: @user, media_id: "test3", title: "XXXX")

      get "index",
          params: { exclude: %w[sources tracks], sort: "title", order: "asc", search_term: "YYY" }

      result = json_parse(response.body)
      expect(result[0]["title"]).to eq("YYYY")
    end

    it "will sort by title or user_entered_title" do
      course_with_teacher_logged_in
      MediaObject.create!(
        user_id: @user, context: @user, media_id: "test", title: "AAA", user_entered_title: "ZZZ"
      )
      MediaObject.create!(
        user_id: @user, context: @user, media_id: "test2", title: "YYY", user_entered_title: nil
      )
      MediaObject.create!(
        user_id: @user, context: @user, media_id: "test3", title: "CCC", user_entered_title: "XXX"
      )

      get "index", params: { exclude: %w[sources tracks], sort: "title", order: "asc" }

      result = json_parse(response.body)
      expect(result[0]["title"]).to eq("XXX")
      expect(result[1]["title"]).to eq("YYY")
      expect(result[2]["title"]).to eq("ZZZ")
    end
  end

  describe "index_media_attachments" do
    before :once do
      Account.site_admin.enable_feature!(:media_links_use_attachment_id)
    end

    before do
      # We don't actually want to ping kaltura during these tests
      allow(MediaObject).to receive(:media_id_exists?).and_return(true)
      allow_any_instance_of(MediaObject).to receive(:media_sources).and_return(
        [{ url: "whatever man", bitrate: 12_345 }]
      )
    end

    it "routes media_attachments to index" do
      expect(get: "api/v1/media_attachments").to route_to(format: "json", controller: "media_objects", action: "index")
    end

    it "retrieves all MediaObjects in the user's context" do
      user_factory
      user_session(@user)
      course_factory
      mo1 =
        MediaObject.create!(user_id: @user, context: @user, media_id: "test", media_type: "video")
      mo2 =
        MediaObject.create!(
          user_id: @user, context: @user, media_id: "test2", media_type: "audio", title: "The Title"
        )
      MediaObject.create!(
        user_id: @user, context: @course, media_id: "test3", user_entered_title: "User Title"
      )

      get "index"

      expect(json_parse(response.body)).to match_array(
        [
          {
            "can_add_captions" => true,
            "created_at" => mo2.created_at.as_json,
            "media_id" => "test2",
            "media_sources" => [
              {
                "bitrate" => 12_345,
                "label" => "12 kbps",
                "src" => "whatever man",
                "url" => "whatever man"
              }
            ],
            "media_tracks" => [],
            "title" => "The Title",
            "media_type" => "audio",
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test2"
          },
          {
            "can_add_captions" => true,
            "created_at" => mo1.created_at.as_json,
            "media_id" => "test",
            "media_sources" => [
              {
                "bitrate" => 12_345,
                "label" => "12 kbps",
                "src" => "whatever man",
                "url" => "whatever man"
              }
            ],
            "media_tracks" => [],
            "title" => "Untitled",
            "media_type" => "video",
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test"
          }
        ]
      )
    end

    it "will not retrive items you did not create" do
      user1 = user_factory
      user2 = user_factory
      user_session(user1)
      mo1 =
        MediaObject.create!(user_id: user1, context: user1, media_id: "test")
      MediaObject.create!(user_id: user2, context: user2, media_id: "test2")

      get "index", params: { exclude: %w[sources tracks] }

      expect(json_parse(response.body)).to match_array(
        [
          {
            "can_add_captions" => true,
            "created_at" => mo1.created_at.as_json,
            "media_id" => "test",
            "title" => "Untitled",
            "media_type" => nil,
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test"
          }
        ]
      )
    end

    it "will limit return to course media" do
      course_factory
      teacher1 = teacher_in_course(course: @course).user
      teacher2 = teacher_in_course(course: @course).user

      user_session(teacher1)

      mo1 = MediaObject.create!(user_id: teacher2, context: @course, media_id: "test")
      MediaObject.create!(user_id: teacher1, context: teacher1, media_id: "another_test")

      get "index", params: { course_id: @course.id, exclude: %w[sources tracks] }

      expect(json_parse(response.body)).to match_array(
        [
          {
            "can_add_captions" => true,
            "created_at" => mo1.created_at.as_json,
            "media_id" => "test",
            "title" => "Untitled",
            "media_type" => nil,
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/test"
          }
        ]
      )
    end

    it "will limit return to group media" do
      course_with_teacher_logged_in(active_all: true)
      gcat = @course.group_categories.create!(name: "My Group Category")
      @group = Group.create!(name: "some group", group_category: gcat, context: @course)

      mo1 = MediaObject.create!(user_id: @user, context: @group, media_id: "in_group")

      MediaObject.create!(user_id: @user, context: @course, media_id: "in_course_with_att")

      MediaObject.create!(user_id: @user, context: @user, media_id: "not_in_course")

      get "index", params: { group_id: @group.id, exclude: %w[sources tracks] }

      expect(json_parse(response.body)).to match_array(
        [
          {
            "media_id" => "in_group",
            "media_type" => nil,
            "created_at" => mo1.created_at.as_json,
            "title" => "Untitled",
            "can_add_captions" => true,
            "embedded_iframe_url" => "http://test.host/media_objects_iframe/in_group"
          }
        ]
      )
    end
  end

  describe "PUT update_media_object" do
    it "returns a 401 if the MediaObject doesn't exist" do
      course_with_teacher_logged_in
      put "update_media_object",
          params: { media_object_id: "anything", user_entered_title: "new title" }
      assert_status(401)
    end

    it "returns a 401 if the MediaObject doesn't belong to the current user" do
      course_with_teacher_logged_in
      another_user = user_factory
      MediaObject.create!(user_id: another_user, media_id: "another-video")
      put "update_media_object",
          params: { media_object_id: "another-video", user_entered_title: "new title" }
      assert_status(401)
    end

    it "requires a logged in user" do
      another_user = user_factory
      MediaObject.create!(user_id: another_user, media_id: "another-video")
      put "update_media_object",
          params: { media_object_id: "another-video", user_entered_title: "new title" }
      assert_status(302) # redirect to login
    end

    it "returns the updated MediaObject" do
      course_with_teacher_logged_in
      MediaObject.create!(user_id: @user, media_id: "the-video", title: "filename.mov")
      put "update_media_object",
          params: { media_object_id: "the-video", user_entered_title: "new title" }

      assert_status(200)
      json = response.parsed_body
      expect(json["title"]).to eq("new title")
    end

    context "adheres to attachment permissions" do
      before :once do
        attachment_model(context: @course)
      end

      it "allows teacher to update MediaObject" do
        user_session(@teacher)
        @attachment.update(content_type: "video", media_entry_id: "maybe")

        expect(@attachment.grants_right?(@teacher, :update)).to be(true)

        MediaObject.create!(user_id: @teacher, media_id: "maybe")
        put "update_media_object", params: { attachment_id: @attachment.id, user_entered_title: "new title" }
        assert_status(200)
      end

      it "disallows access for unauthorized user" do
        user_model
        user_session(@user)
        @attachment.update(content_type: "video", media_entry_id: "maybe")

        expect(@attachment.grants_right?(@user, :update)).to be(false)

        MediaObject.create!(user_id: @teacher, media_id: "maybe")
        put "update_media_object", params: { attachment_id: @attachment.id, user_entered_title: "new title" }
        assert_status(401)
      end
    end
  end

  describe "GET /media_objects_iframe/:id" do
    before do
      allow(MediaObject).to receive(:media_id_exists?).and_return(true)
      allow_any_instance_of(MediaObject).to receive(:media_sources).and_return(
        [{ url: "whatever man", bitrate: 12_345 }]
      )
    end

    it "does not include content-security-policy headers" do
      course_with_teacher_logged_in
      get "iframe_media_player", params: { media_object_id: "the-video" }

      assert_status(200)
      expect(response.headers["content-security-policy"]).to be_nil
    end
  end

  describe "GET 'media_attachments_iframe'" do
    before do
      @media_object = @course.media_objects.create! media_id: "0_deadbeef", user_entered_title: "blah.flv"
      allow_any_instance_of(MediaObject).to receive(:media_sources).and_return(
        [{ url: "whatever man", bitrate: 12_345 }]
      )
    end

    it "returns an error if the media is locked" do
      user_session(@student)
      attachment = @media_object.attachment
      attachment.update(locked: true)

      get "iframe_media_player", params: { attachment_id: attachment.id }
      assert_status(401)
    end

    it "finds a replaced file" do
      user_session(@student)
      old = @media_object.attachment
      old.file_state = "deleted"
      old.replacement_attachment = attachment_model(media_entry_id: "0_deadbeef", filename: "blah.flv", media_object: @media_object)
      old.save!

      get "iframe_media_player", params: { attachment_id: old.id }
      assert_status(200)
    end

    it "returns media tracks urls in the javascript environment" do
      user_session(@student)
      expect(controller).to receive(:media_attachment_api_json).and_call_original
      get "iframe_media_player", params: { attachment_id: @media_object.attachment_id }
      assert_status(200)
    end
  end

  describe "#media_attachment_api_json" do
    before do
      @media_object = @course.media_objects.create! media_id: "0_deadbeef", user_entered_title: "blah.flv"
      @attachment = @media_object.attachment
      allow_any_instance_of(MediaObject).to receive(:media_sources).and_return(
        [{ url: "whatever man", bitrate: 12_345 }]
      )
    end

    it "returns parent-inherited media tracks" do
      original_attachment = @attachment
      en_track = @media_object.media_tracks.create!(kind: "subtitles", locale: "en", content: "en subs", user_id: @teacher)
      other_attachment = attachment_model(media_entry_id: @media_object.media_id, filename: "blah2.flv")
      fra_track = other_attachment.media_tracks.create!(kind: "subtitles", locale: "fr", content: "fr new", user_id: @teacher)
      expect(other_attachment.media_tracks_include_originals).to match [en_track, fra_track]
      user_session(@student)
      media_attachment_api_json = controller.media_attachment_api_json(other_attachment, @media_object, @student, session)
      expect(media_attachment_api_json["media_tracks"].pluck("locale")).to include("en", "fr")
      media_attachment_api_json = controller.media_attachment_api_json(original_attachment, @media_object, @student, session)
      expect(media_attachment_api_json["media_tracks"].pluck("locale")).to eq(["en"])
    end

    it "returns media_attachment_iframe_url for the embedded_iframe_url" do
      user_session(@student)
      media_attachment_api_json = controller.media_attachment_api_json(@attachment, @media_object, @student, session)
      expect(media_attachment_api_json["embedded_iframe_url"]).to eq("http://test.host/media_attachments_iframe/#{@attachment.id}")
    end

    context "can_add_captions" do
      it "returns true if the user can add captions to the media object and update the attachment" do
        user_session(@teacher)
        expect(@attachment.grants_right?(@teacher, :update)).to be(true)
        expect(@media_object.grants_right?(@teacher, :add_captions)).to be(true)

        media_attachment_api_json = controller.media_attachment_api_json(@attachment, @media_object, @teacher, session)
        expect(media_attachment_api_json["can_add_captions"]).to be(true)
      end

      it "returns false if the user cannot add captions to the media object" do
        teacher_role = Role.get_built_in_role("TeacherEnrollment", root_account_id: @course.root_account.id)
        RoleOverride.create!(
          permission: "manage_content",
          enabled: false,
          role: teacher_role,
          account: @course.root_account
        )
        expect(@attachment.grants_right?(@teacher, :update)).to be(true)
        expect(@media_object.grants_right?(@teacher, :add_captions)).to be(false)

        user_session(@teacher)
        media_attachment_api_json = controller.media_attachment_api_json(@attachment, @media_object, @teacher, session)
        expect(media_attachment_api_json["can_add_captions"]).to be(false)
      end

      it "returns false if the user cannot update the attachment" do
        teacher_role = Role.get_built_in_role("TeacherEnrollment", root_account_id: @course.root_account.id)
        RoleOverride.create!(
          permission: "manage_files_edit",
          enabled: false,
          role: teacher_role,
          account: @course.root_account
        )
        user_session(@teacher)
        expect(@attachment.grants_right?(@teacher, :update)).to be(false)
        expect(@media_object.grants_right?(@teacher, :add_captions)).to be(true)

        user_session(@teacher)
        media_attachment_api_json = controller.media_attachment_api_json(@attachment, @media_object, @teacher, session)
        expect(media_attachment_api_json["can_add_captions"]).to be(false)
      end
    end
  end

  describe "GET '/media_objects/:id/thumbnail" do
    it "redirects to kaltura even if the MediaObject does not exist" do
      allow(CanvasKaltura::ClientV3).to receive(:config).and_return({})
      expect_any_instance_of(CanvasKaltura::ClientV3).to receive(:thumbnail_url).and_return(
        "http://test.host/thumbnail_redirect"
      )
      get :media_object_thumbnail, params: { media_object_id: "0_notexist", width: 100, height: 100 }

      expect(response).to be_redirect
      expect(response.location).to eq "http://test.host/thumbnail_redirect"
    end
  end

  describe "POST '/media_objects'" do
    before do
      user_session(@student)
    end

    it "matches the create_media_object route" do
      assert_recognizes(
        { controller: "media_objects", action: "create_media_object" },
        { path: "media_objects", method: :post }
      )
    end

    it "matches the create_media_attachment route" do
      assert_recognizes(
        { controller: "media_objects", action: "create_media_object" },
        { path: "media_attachments", method: :post }
      )
    end

    it "updates the object if it already exists" do
      @media_object = @user.media_objects.build(media_id: "new_object")
      @media_object.media_type = "audio"
      @media_object.title = "original title"
      @media_object.save

      @original_count = @user.media_objects.count

      post :create_media_object,
           params: {
             context_code: "user_#{@user.id}",
             id: @media_object.media_id,
             type: @media_object.media_type,
             title: "new title"
           }

      @media_object.reload
      expect(@media_object.title).to eq "new title"

      @user.reload
      expect(@user.media_objects.count).to eq @original_count
    end

    it "creates the object if it doesn't already exist" do
      @original_count = @user.media_objects.count

      post :create_media_object,
           params: {
             context_code: "user_#{@user.id}", id: "new_object", type: "audio", title: "title"
           }

      @user.reload
      expect(@user.media_objects.count).to eq @original_count + 1
      @media_object = @user.media_objects.last

      expect(@media_object.media_id).to eq "new_object"
      expect(@media_object.media_type).to eq "audio"
      expect(@media_object.title).to eq "title"
    end

    it "truncates the title and user_entered_title" do
      post :create_media_object,
           params: {
             context_code: "user_#{@user.id}",
             id: "new_object",
             type: "audio",
             title: "x" * 300,
             user_entered_title: "y" * 300
           }
      @media_object = @user.reload.media_objects.last
      expect(@media_object.title.size).to be <= 255
      expect(@media_object.user_entered_title.size).to be <= 255
    end

    it "returns the embedded_iframe_url" do
      post :create_media_object,
           params: {
             context_code: "user_#{@user.id}", id: "new_object", type: "audio", title: "title"
           }
      @media_object = @user.reload.media_objects.last
      expect(response.parsed_body["embedded_iframe_url"]).to eq media_object_iframe_url(
        @media_object.media_id
      )
    end
  end

  describe "#media_sources_json" do
    before do
      @media_object = @course.media_objects.create! media_id: "0_deadbeef", user_entered_title: "blah.flv"
      allow_any_instance_of(MediaObject).to receive(:media_sources).and_return(
        [{ url: "whatever man", bitrate: 12_345 }]
      )
    end

    it "returns the media object url as the source" do
      expect(controller.media_sources_json(@media_object)).to eq(
        [
          {
            bitrate: 12_345,
            label: "12 kbps",
            src: "whatever man",
            url: "whatever man"
          }
        ]
      )
    end

    context "with authenticated_iframe_content feature flag enabled" do
      before do
        Account.site_admin.enable_feature!(:authenticated_iframe_content)
      end

      it "returns the redirect url as the source" do
        expect(controller.media_sources_json(@media_object)).to eq(
          [
            {
              bitrate: 12_345,
              label: "12 kbps",
              src: "http://test.host/media_objects/#{@media_object.id}/redirect?bitrate=12345",
              url: "http://test.host/media_objects/#{@media_object.id}/redirect?bitrate=12345"
            }
          ]
        )
      end
    end
  end

  describe "GET '/media_objects/:id/redirect'" do
    before do
      allow(CanvasKaltura::ClientV3).to receive(:config).and_return({})
      allow_any_instance_of(CanvasKaltura::ClientV3).to receive(:assetSwfUrl).and_return(
        "http://test.host/media_redirect"
      )
      @media_object = @course.media_objects.create! media_id: "0_deadbeef", user_entered_title: "blah.flv"
      user_session(@teacher)
    end

    context "with authenticated_iframe_content feature flag enabled" do
      before do
        Account.site_admin.enable_feature!(:authenticated_iframe_content)
        allow_any_instance_of(CanvasKaltura::ClientV3).to receive(:media_sources).and_return(
          [
            { bitrate: 1, url: "http://test.host/media_redirect" },
            { bitrate: 2, url: "http://test.host/media_redirect_2" }
          ]
        )
        @attachment = @media_object.attachment
      end

      it "returns the file" do
        temp_file = Tempfile.new("foo")
        expect(controller).to receive(:media_source_temp_file).with("http://test.host/media_redirect").and_return(temp_file)
        expect(controller).to receive(:send_file).with(temp_file, filename: @attachment.filename, type: @attachment.content_type, stream: true).and_call_original
        get :media_object_redirect, params: { id: @media_object.id }
      end

      it "returns the file by bitrate" do
        temp_file = Tempfile.new("foo")
        expect(controller).to receive(:media_source_temp_file).with("http://test.host/media_redirect_2").and_return(temp_file)
        expect(controller).to receive(:send_file).with(temp_file, filename: @attachment.filename, type: @attachment.content_type, stream: true).and_call_original
        get :media_object_redirect, params: { id: @media_object.id, bitrate: 2 }
      end

      it "returns the first file if the bitrate is invalid" do
        temp_file = Tempfile.new("foo")
        expect(controller).to receive(:media_source_temp_file).with("http://test.host/media_redirect").and_return(temp_file)
        expect(controller).to receive(:send_file).with(temp_file, filename: @attachment.filename, type: @attachment.content_type, stream: true).and_call_original
        get :media_object_redirect, params: { id: @media_object.id, bitrate: "not real" }
      end

      it "renders an error if there was a problem fetching the file" do
        allow(controller).to receive(:media_source_temp_file).and_raise(CanvasHttp::InvalidResponseCodeError.new(400, "error fetching url"))
        get :media_object_redirect, params: { id: @media_object.id }
        assert_status(400)
      end
    end
  end
end
