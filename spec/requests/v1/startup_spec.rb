require "spec_helper"

describe "Startup Requests" do
  include V1ApiSpecHelper
  include UserSpecHelper
  include Rails.application.routes.url_helpers

  let!(:startup) { create(:startup, { approval_status: Startup::APPROVAL_STATUS_APPROVED, name: 'startup 1' }) }
  let!(:startup1) { create(:startup, { approval_status: Startup::APPROVAL_STATUS_APPROVED, name: 'startup 2' }) }
  let!(:startup2) { create(:startup, { approval_status: Startup::APPROVAL_STATUS_APPROVED, name: 'foobar 1' }) }
  let!(:startup3) { create(:startup, { approval_status: Startup::APPROVAL_STATUS_APPROVED, name: 'foobar 2' }) }

  def emails_sent
    ActionMailer::Base.deliveries
  end

  it "fetch startups on index" do
    get "/api/startups", {}, version_header
    expect(response).to render_template(:index)
    response.body.should have_json_path("0/id")
    response.body.should have_json_path("0/name")
    response.body.should have_json_path("0/logo_url")
    response.body.should have_json_path("0/pitch")
    response.body.should have_json_path("0/website")
    response.body.should have_json_path("0/created_at")
  end

  it "fetch startups within a category" do
    get "/api/startups", { category: startup1.categories.first.name }, version_header
    expect(response).to render_template(:index)
    response.body.should have_json_size(1).at_path("/")
    response.body.should have_json_path("0/id")
    response.body.should have_json_path("0/name")
    response.body.should have_json_path("0/logo_url")
    response.body.should have_json_path("0/pitch")
    response.body.should have_json_path("0/website")
    response.body.should have_json_path("0/created_at")
  end

  it "fetches related startups when searched for" do
    get "/api/startups", { search_term: 'foobar' }, version_header
    expect(response).to render_template(:index)
    response.body.should have_json_size(2).at_path("/")
    response.body.should have_json_path("0/id")
    response.body.should have_json_path("0/name")
    response.body.should have_json_path("0/logo_url")
    response.body.should have_json_path("0/pitch")
    response.body.should have_json_path("0/website")
    response.body.should have_json_path("0/created_at")
  end

  it "fetches one startup with " do
    get "/api/startups/#{startup.id}", {}, version_header
    expect(response).to render_template(:show)
    response.body.should have_json_path("id")
    response.body.should have_json_path("name")
    response.body.should have_json_path("logo_url")
    response.body.should have_json_path("pitch")
    response.body.should have_json_path("website")
    response.body.should have_json_path("about")
    response.body.should have_json_path("email")
    response.body.should have_json_path("phone")
    response.body.should have_json_path("twitter_link")
    response.body.should have_json_path("facebook_link")
    response.body.should have_json_type(Array).at_path("categories")
    response.body.should have_json_type(Array).at_path("founders")
    response.body.should have_json_path("founders/0/id")
    response.body.should have_json_path("founders/0/name")
    response.body.should have_json_path("founders/0/title")
    response.body.should have_json_path("founders/0/picture_url")
    response.body.should have_json_path("founders/0/linkedin_url")
    response.body.should have_json_path("founders/0/twitter_url")
  end

  describe 'POST /startups' do
    context 'when there are parameters' do
      it 'creates a startup with parameters for authenticated user' do
        post '/api/startups', { startup: attributes_for(:startup_application) }, version_header
        expect(response.code).to eq '201'
        have_startup_object response
      end
    end

    context 'when no parameters are given' do
      it 'creates an empty startup for authenticated user' do
        post '/api/startups', {}, version_header
        expect(response.code).to eq '201'
        have_startup_object response
      end
    end

    context 'when user already has a startup' do
      it 'raises error UserAlreadyHasStartup' do
        vh = version_header(create(:user_with_out_password, startup: (create :startup)))
        post '/api/startups', { startup: attributes_for(:startup_application) }, vh
        expect(response.code).to eq '422'
        expect(parse_json response.body, 'code').to eq 'UserAlreadyHasStartup'
      end
    end
  end

  it "fetches suggestions based on given term" do
    get "/api/startups/load_suggestions", { term: 'fo' }, version_header
    expect(response.body).to have_json_size(2).at_path("/")
    expect(response.body).to have_json_path("0/id")
    expect(response.body).to have_json_path("0/name")
    expect(response.body).to have_json_path("0/logo_url")
  end

  context "request to add new founder to a startup" do
    let(:startup) { create :startup }
    let(:new_employee) { create :user_with_out_password }

    before(:each) do
      ActionMailer::Base.deliveries = []
      UserPushNotifyJob.stub_chain(:new, :async, perform: true) # TODO: Change this to allow statement in Rspec v3.
    end

    context 'if auth_token is not given' do
      it 'returns error with code AuthTokenInvalid' do
        post "/api/startups/#{startup.id}/link_employee", { employee_id: new_employee.id }, {}
        expect(parse_json(response.body, 'code')).to eq 'AuthTokenInvalid'
      end
    end

    it "sends email to all existing co-founders" do
      post "/api/startups/#{startup.id}/link_employee", { position: 'startup ceo' }, version_header(new_employee)
      new_employee.reload
      expect(emails_sent.last.body.to_s).to include(confirm_employee_startup_url(startup, token: new_employee.startup_verifier_token))
      expect(new_employee.startup_link_verifier_id).to eql(nil)
      expect(new_employee.title).to eql('startup ceo')
      expect(new_employee.reload.startup_id).to eql(startup.id)
      expect(response).to be_success
      have_user_object(response, 'user')
    end
  end

  describe 'POST /startups/:id/founders' do
    let(:user) { create :user_with_out_password, startup: startup }

    before(:each) do
      ActionMailer::Base.deliveries = []
      UserPushNotifyJob.stub_chain(:new, :async, perform: true) # TODO: Change this to allow statement in Rspec v3.
    end

    context "when requested startup does not match authorized user's startup" do
      let(:user) { create :user_with_out_password, startup: startup1 }

      it 'responds with error code AuthorizedUserStartupMismatch' do
        post "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
        expect(response.code).to eq '422'
        expect(parse_json(response.body, 'code')).to eq 'AuthorizedUserStartupMismatch'
      end
    end

    shared_examples_for 'new cofounder' do
      it 'sends an email to cofounder address' do
        post "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in', fullname: 'James P Sullivan' }, version_header(user)
        expect(emails_sent.last.body.to_s).to include "invited to join #{user.fullname}'s startup as a co-founder"
      end

      it 'sets the user pending_startup_id' do
        post "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
        cofounder = User.find_by(email: 'james.p.sullivan@mobme.in')
        expect(cofounder.pending_startup_id).to eq startup.id
      end
    end

    context 'when cofounder does not exist' do
      it_behaves_like 'new cofounder'

      it 'sets a invitation token to indicate invited status' do
        post "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
        created_user = User.find_by(email: 'james.p.sullivan@mobme.in')
        expect(created_user.invitation_token).to_not eq nil
      end
    end

    context 'when cofounder exists as user' do
      context 'when user already belongs to a startup' do
        it 'responds with error code UserAlreadyMemberOfStartup' do
          create :user_with_out_password, email: 'james.p.sullivan@mobme.in', startup: startup2
          post "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
          expect(response.code).to eq '422'
          expect(parse_json(response.body, 'code')).to eq 'UserAlreadyMemberOfStartup'
        end
      end

      context 'when user already has pending invitation' do
        it 'responds with error code UserHasPendingStartupInvite' do
          create :user_with_out_password, email: 'james.p.sullivan@mobme.in', pending_startup_id: startup2.id
          post "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
          expect(response.code).to eq '422'
          expect(parse_json(response.body, 'code')).to eq 'UserHasPendingStartupInvite'
        end
      end

      context 'when user does not belong to any startup' do
        before do
          create :user_with_out_password, email: 'james.p.sullivan@mobme.in'
        end

        it 'sends a notification to user' do
          # TODO: How to test sending of notifications?
        end

        it_behaves_like 'new cofounder'

        it 'does not set invitation token' do
          post "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
          created_user = User.find_by(email: 'james.p.sullivan@mobme.in')
          expect(created_user.invitation_token).to eq nil
        end
      end
    end
  end

  describe 'DELETE /startups/:id/founders' do
    let(:user) { create :user_with_out_password, startup: startup }

    context "when requested startup does not match authorized user's startup" do
      let(:user) { create :user_with_out_password, startup: startup1 }

      it 'responds with error code AuthorizedUserStartupMismatch' do
        delete "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
        expect(response.code).to eq '422'
        expect(parse_json(response.body, 'code')).to eq 'AuthorizedUserStartupMismatch'
      end
    end

    context 'when user does not exist' do
      it 'responds with error code FounderMissing' do
        delete "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
        expect(response.code).to eq '404'
        expect(parse_json(response.body, 'code')).to eq 'FounderMissing'
      end
    end

    context 'when user does not have pending_startup_id' do
      it 'responds with error code UserIsNotPendingFounder' do
        create :user_with_out_password, email: 'james.p.sullivan@mobme.in'
        delete "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
        expect(response.code).to eq '422'
        expect(parse_json(response.body, 'code')).to eq 'UserIsNotPendingFounder'
      end
    end

    context "when user belongs to startup other than authorized user's" do
      it 'responds with error code UserPendingStartupMismatch' do
        create :user_with_out_password, email: 'james.p.sullivan@mobme.in', pending_startup_id: startup1.id
        delete "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
        expect(response.code).to eq '422'
        expect(parse_json(response.body, 'code')).to eq 'UserPendingStartupMismatch'
      end
    end

    context "when user is pending founder on authorized user's startup" do
      it 'deletes pending user' do
        pending_cofounder = create :user_with_out_password, email: 'james.p.sullivan@mobme.in', pending_startup_id: startup.id

        delete "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)

        expect(response.code).to eq '200'
        expect { pending_cofounder.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'GET /api/startups/:id/founders' do
    let(:user) { create :user_with_out_password, startup: startup }

    context "when requested startup does not match authorized user's startup" do
      let(:user) { create :user_with_out_password, startup: startup1 }

      it 'responds with error code AuthorizedUserStartupMismatch' do
        get "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
        expect(response.code).to eq '422'
        expect(parse_json(response.body, 'code')).to eq 'AuthorizedUserStartupMismatch'
      end
    end

    context 'when user does not exist' do
      it 'responds with error code FounderMissing' do
        get "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
        expect(response.code).to eq '404'
        expect(parse_json(response.body, 'code')).to eq 'FounderMissing'
      end
    end

    context 'when user is pending cofounder' do
      it 'returns status pending' do
        create :user_with_out_password, email: 'james.p.sullivan@mobme.in', pending_startup_id: user.startup.id
        get "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
        expect(response.code).to eq '200'
        expect(parse_json(response.body, '0/status')).to eq User::COFOUNDER_PENDING
      end
    end

    context 'when user is accepted cofounder' do
      it 'returns status accepted' do
        create :user_with_out_password, email: 'james.p.sullivan@mobme.in', startup: user.startup
        get "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
        expect(response.code).to eq '200'
        expect(parse_json(response.body, '0/status')).to eq User::COFOUNDER_ACCEPTED
      end
    end

    context 'when user is rejected cofounder' do
      it 'returns status rejected' do
        create :user_with_out_password, email: 'james.p.sullivan@mobme.in', startup: startup1
        get "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in' }, version_header(user)
        expect(response.code).to eq '200'
        expect(parse_json(response.body, '0/status')).to eq User::COFOUNDER_REJECTED
      end
    end

    context 'when no email is supplied' do
      it 'returns status of all users' do
        create :user_with_out_password, email: 'james.p.sullivan@mobme.in', pending_startup_id: user.startup.id
        create :user_with_out_password, email: 'boo@mobme.in', startup: user.startup
        create :user_with_out_password, email: 'mike.wazowski@mobme.in', startup: startup1

        get "/api/startups/#{startup.id}/founders", { email: 'james.p.sullivan@mobme.in,boo@mobme.in,mike.wazowski@mobme.in' }, version_header(user)
        expect(response.code).to eq '200'
        expect(parse_json(response.body)).to eq(
          [
            {
              'email' => 'james.p.sullivan@mobme.in',
              'status' => 'pending'
            },
            {
              'email' => 'boo@mobme.in',
              'status' => 'accepted'
            },
            {
              'email' => 'mike.wazowski@mobme.in',
              'status' => 'rejected'
            }
          ]
        )
      end
    end
  end

  describe 'POST /api/startups/:id/incubate' do
    let(:user) { create :user_with_out_password, startup: startup }

    context "when requested startup does not match authorized user's startup" do
      let(:user) { create :user_with_out_password, startup: startup1 }

      it 'responds with error code AuthorizedUserStartupMismatch' do
        post "/api/startups/#{startup.id}/incubate", {}, version_header(user)
        expect(response.code).to eq '422'
        expect(parse_json(response.body, 'code')).to eq 'AuthorizedUserStartupMismatch'
      end
    end

    context 'when the startup approval status is not nil' do


      it 'responds with error code StartupInvalidApprovalState' do
        post "/api/startups/#{startup.id}/incubate", {}, version_header(user)
        expect(response.code).to eq '422'
        expect(parse_json(response.body, 'code')).to eq 'StartupInvalidApprovalState'
      end
    end

    context 'when the startup approval status is nil' do
      let(:startup) { create(:startup) }

      it 'sets approval status of startup to pending' do
        post "/api/startups/#{startup.id}/incubate", {}, version_header(user)
        expect(response.code).to eq '200'
        startup.reload
        expect(startup.approval_status).to eq Startup::APPROVAL_STATUS_PENDING
      end
    end
  end

  describe 'PUT /api/startups/:id' do
    context 'when supplied comma-separated category ID-s' do
      let(:startup) { create :startup }
      let(:user) { create :user_with_out_password, startup: startup }
      let(:category_1) { create :startup_category }
      let(:category_2) { create :startup_category }

      it 'sets categories' do
        put "/api/startups/#{startup.id}", { startup: { categories: "#{category_1.id},#{category_2.id}" } }, version_header(user)
        expect(response.code).to eq '200'
        startup.reload
        expect(startup.categories).to eq [category_1, category_2]
      end
    end
  end
end
