require "omnicontacts/parse_utils"
require "omnicontacts/middleware/oauth2"

module OmniContacts
  module Importer
    class Gmail < Middleware::OAuth2
      include ParseUtils

      attr_reader :auth_host, :authorize_path, :auth_token_path, :scope

      def initialize *args
        super *args
        @auth_host = "accounts.google.com"
        @authorize_path = "/o/oauth2/auth"
        @auth_token_path = "/o/oauth2/token"
        @scope = (args[3] && args[3][:scope]) || "https://www.googleapis.com/auth/contacts.readonly https://www.googleapis.com/auth/userinfo#email https://www.googleapis.com/auth/userinfo.profile"
        @contacts_host = "people.googleapis.com" #"www.google.com" https:///v1/{resourceName=people/*}/connections
        @contacts_path = "/v1/people/me/connections" #"/m8/feeds/contacts/default/full"
        @max_results = (args[3] && args[3][:max_results]) || 100
        @self_host = "people.googleapis.com" #"www.googleapis.com"
        @profile_path = "/v1/people/me" #"/oauth2/v3/userinfo"
      end

      def fetch_contacts_using_access_token access_token, token_type
        fetch_current_user(access_token, token_type)
        contacts_response = https_get(@contacts_host, @contacts_path, contacts_req_params, contacts_req_headers(access_token, token_type))
        contacts_from_response(contacts_response, access_token)
      end

      def fetch_current_user access_token, token_type
        self_response = https_get(@self_host, @profile_path, contacts_req_params, contacts_req_headers(access_token, token_type))
        user = current_user(self_response, access_token, token_type)
        set_current_user user
      end

      private

      def contacts_req_params
        { 'pageSize' => '2', 'personFields' => 'names,emailAddresses' }
      end

      def contacts_req_headers token, token_type
        {"GData-Version" => "3.0", "Authorization" => "#{token_type} #{token}"}
      end

      def contacts_from_response(response_as_json, access_token)
        response = JSON.parse(response_as_json)
        Rails.logger.info("!@!@!@!@! RESPONSE JSON")
        Rails.logger.info(response)
        contacts = []
        return contacts if response.blank?
        response['connections'].each do |entry|
          # creating nil fields to keep the fields consistent across other networks

          contact = { :id => nil,
                      :first_name => nil,
                      :last_name => nil,
                      :name => nil,
                      :emails => nil,
                      :gender => nil,
                      :birthday => nil,
                      :profile_picture=> nil,
                      :relation => nil,
                      :addresses => nil,
                      :phone_numbers => nil,
                      :dates => nil,
                      :company => nil,
                      :position => nil
          }
          next if entry['names'].blank?
          contact[:id] = entry['names'][0]['metadata']['source']['id']
          contact[:first_name] = entry['names'][0]['givenName'] if entry['names'][0]['givenName']
          contact[:last_name] = entry['names'][0]['familyName'] if entry['names'][0]['familyName']
          contact[:name] = full_name(contact[:first_name],contact[:last_name])
          contact[:email] = entry['emailAddresses'][0]['value'] if entry['emailAddresses']
          contact[:first_name], contact[:last_name], contact[:name] = email_to_name(contact[:email]) if (contact[:name].nil? && contact[:email])

          contacts << contact if contact[:email]
        end
        contacts.uniq! {|c| c[:email] || c[:profile_picture] || c[:name]}
        contacts
      end

      def current_user me, access_token, token_type
        return nil if me.nil?
        me = JSON.parse(me)
        user = {:id => me['id'], :email => me['email'], :name => me['name'], :first_name => me['given_name'],
                :last_name => me['family_name'], :gender => me['gender'], :birthday => birthday(me['birthday']), :profile_picture => me["picture"],
                :access_token => access_token, :token_type => token_type
        }
        user
      end

      def birthday dob
        return nil if dob.nil?
        birthday = dob.split('-')
        return birthday_format(birthday[2], birthday[3], nil) if birthday.size == 4
        return birthday_format(birthday[1], birthday[2], birthday[0]) if birthday.size == 3
      end

      def contact_id(profile_url)
        id = (profile_url.present?) ? File.basename(profile_url) : nil
        id
      end

    end
  end
end
