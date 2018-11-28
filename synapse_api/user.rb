require_relative './http_request'
require 'mime-types'
require 'base64'
require 'open-uri'
require 'json'
require_relative './error'
require_relative './node'
require_relative './nodes'
require_relative './transaction'
require_relative './transactions'

module SynapsePayRest

	class User

		# Valid optional args for #get
    	VALID_QUERY_PARAMS = [:query, :page, :per_page, :full_dehydrate].freeze

    	attr_reader :client
		attr_accessor :user_id,:refresh_token, :oauth_key, :expires_in, :payload, :full_dehydrate

		def initialize(user_id:,refresh_token:, client:,payload:, full_dehydrate:)
			@user_id = user_id
			@client = client
			@refresh_token = refresh_token
			@payload =payload
			@full_dehydrate =full_dehydrate
		end

		# adding to base doc after base doc is created 
		# pass in full payload 
		# function used to make a base doc go away and update sub-doc
		# see https://docs.synapsefi.com/docs/updating-existing-document
		def update_base_doc(documents)
			path = get_user_path(user_id: self.user_id)
     begin
       client.patch(path, documents)
     rescue SynapsePayRest::Error::Unauthorized
       self.authenticate()
       client.patch(path, documents)
     end
			nil 
		end

	    # Queries Synapse API for all nodes belonging to user (with optional
        # filters) and returns them as node instances.
        # @param page [String,Integer] (optional) response will default to 1
        # @param per_page [String,Integer] (optional) response will default to 20
        # @param type [String] (optional)
	    # @see https://docs.synapsepay.com/docs/node-resources node types
	    # @return [Array<SynapsePayRest::Nodes>] 
		def get_all_nodes(**options)
			[options[:page], options[:per_page]].each do |arg|
				if arg && (!arg.is_a?(Integer) || arg < 1)
					raise ArgumentError, "#{arg} must be nil or an Integer >= 1"
				end
			end
			path = nodes_path(options: options)
      begin
       nodes = client.get(path)
      rescue SynapsePayRest::Error::Unauthorized
       self.authenticate()
       nodes = client.get(path)
      end

			return [] if nodes["nodes"].empty?
			response = nodes["nodes"].map { |node_data| Node.new(node_id: node_data['_id'], user_id: node_data['user_id'], http_client: client, payload: node_data, full_dehydrate: "no")}
			nodes = Nodes.new(limit: nodes["limit"], page: nodes["page"], page_count: nodes["page_count"], node_count: nodes["node_count"], payload: response, http_client: client)
		end


		# Queries Synapse get user API for users refresh_token
        # @param full_dehydrate [Boolean] 
	    # @see https://docs.synapsefi.com/docs/get-user
	    # @return refresh_token string
		def refresh_token(**options)
			options[:full_dehydrate] = "yes" if options[:full_dehydrate] == true
			options[:full_dehydrate] = "no" if options[:full_dehydrate] == false

			path = get_user_path(user_id: self.user_id, options: options)
			response = client.get(path)
			refresh_token = response["refresh_token"]
			refresh_token 
		end

		# Quaries Synapse get oauth API for user after extracting users refresh token
		# @params scope [Array<Strings>]
		# Function does not suppor registering new fingerprint
		def authenticate(**options)
			payload = payload_for_refresh(refresh_token: self.refresh_token())
			path = oauth_path(options: options)
			oauth_response = client.post(path, payload)
			oauth_key = oauth_response['oauth_key']
			oauth_expires = oauth_response['expires_in']
			self.oauth_key = oauth_key
			self.expires_in = oauth_expires
			# self.expire = 0 
			# seld. authenticate 
			client.update_headers(oauth_key: oauth_key)
			self 
		end

		# Returns users information
		def info
			user = {:id => self.user_id, :full_dehydrate => self.full_dehydrate, :payload => self.payload}
			JSON.pretty_generate(user)
		end

		# Quaries Synapse get user for user 
		# un-index a user, changing permission scope 
		def delete_user
			path = get_user_path(user_id: self.user_id)
			permission = { "permission": "MAKE-IT-GO-AWAY" }

      begin
       client.patch(path, permission)
      rescue SynapsePayRest::Error::Unauthorized
        self.authenticate()
       client.patch(path, permission)
      end

			nil 
		end

	  # Queries the Synapse API get all user transactions belonging to a user and returns
      # them as Transactions instances [Array<SynapsePayRest::Transactions>] 
      # @param options[:page] [String,Integer] (optional) response will default to 1
      # @param options[:per_page} [String,Integer] (optional) response will default to 20
    def get_transactions(**options)
  		[options[:page], options[:per_page]].each do |arg|
  			if arg && (!arg.is_a?(Integer) || arg < 1)
  				raise ArgumentError, "#{arg} must be nil or an Integer >= 1"
  			end
  		end

      path = transactions_path(user_id: self.user_id, options: options)

      begin
        trans = client.get(path)
      rescue SynapsePayRest::Error::Unauthorized
        self.authenticate()
        trans = client.get(path)
      end

      
      response = trans["trans"].map { |trans_data| Transaction.new(trans_id: trans_data['_id'], http_client: client, payload: trans_data)}
      trans = Transactions.new(limit: trans["limit"], page: trans["page"], page_count: trans["page_count"], trans_count: trans["trans_count"], payload: response, http_client: client)

    	trans
    end

      # Creates a new node in the API associated to the provided user and
      # returns a node instance from the response data
      # @param nickname [String]
      # @param type [String]
      # @see https://docs.synapsefi.com/docs/deposit-accounts for example
      # @return [SynapsePayRest::Node]
		def create_node(payload:)
			path = get_user_path(user_id: self.user_id)
			path = path + nodes_path
	
      begin
       response = client.post(path,payload)
      rescue SynapsePayRest::Error::Unauthorized
       self.authenticate()
       response = client.post(path,payload)
      end

			
			node = Node.new(
				user_id: self.user_id,
				node_id: response["nodes"][0]["_id"],
				full_dehydrate: "no",
				http_client: client, 
				payload: response
				)
			node
		end

		def get_node(node_id:, **options)
			path = nodes_path()
			path = get_user_path(user_id: self.user_id) + path + "/#{node_id}"
			puts path 
			node = client.get(path)

      begin
       node = client.get(path)
      rescue SynapsePayRest::Error::Unauthorized
       self.authenticate()
       node = client.get(path)
      end

	
			node = Node.new(node_id: node['_id'], 
				user_id: node['user_id'], 
				http_client: client, 
				payload: node, 
				full_dehydrate: options[:full_dehydrate] == "yes" ? true : false
				)
			node
		end

		  # Initiates dummy transactions to a node
		  # @param user_id [String]
		  # @param node_id [String]
		def dummy_transactions(node_id:)
			self.authenticate()
			path = get_user_path(user_id: self.user_id) + "/nodes/#{node_id}/dummy-tran" 

      begin
       client.get(path)
      rescue SynapsePayRest::Error::Unauthorized
       self.authenticate()
       client.get(path)
      end
		end



		private

		def oauth_path(**options)
			path = "/oauth/#{self.user_id}"
		end

		def payload_for_refresh(refresh_token:)
			{'refresh_token' => refresh_token}
		end

		def get_user_path(user_id:, **options)
			path = "/users/#{user_id}"
			params = VALID_QUERY_PARAMS.map do |p|
				options[p] ? "#{p}=#{options[p]}" : nil
			end.compact
			path += '?' + params.join('&') if params.any?
			path 
		end

		def transactions_path(user_id:, node_id: nil, **options)
			path = "/users/#{user_id}/trans" 
			params = VALID_QUERY_PARAMS.map do |p|
				options[p] ? "#{p}=#{options[p]}" : nil
			end.compact

			path += '?' + params.join('&') if params.any?
			path
		end

		def nodes_path(**options)
			path = "/nodes"
			params = VALID_QUERY_PARAMS.map do |p|
				options[p] ? "#{p}=#{options[p]}" : nil
			end.compact

			path += '?' + params.join('&') if params.any?
			path
		end
	end
end


#def from_response(response, options = "no", oauth: true)
       # user = User.new(
        #  user_id:                response['_id'],
        #  refresh_token:     response['refresh_token'],
        #  client:            client,
        #  full_dehydrate:    options,
        #  payload:           response
        #)

        #if response.has_key?('flag')
          #user.flag = response['flag']
        #end

        #if response.has_key?('ips')
          #user.ips = response['ips']
        #end

        # add base doc validation 
        # add oauth criteria

        # return is a user object 
        # turning the object to a json 

        # automates authentication upon creating a user  
        # call the authenticate method is  oauth expires 
        #oauth ? user.authenticate : user
      #end

      # to-do create a user from user data
      #def multiple_from_response(response)
      #return [] if response.empty?
      #response.map { |user_data| from_response(user_data, oauth: false)}
      #end


