require 'batch_api/response'

module BatchApi
  # Public: an individual batch operation.
  module Operation
    class Rack
      attr_accessor :method, :url, :params, :headers
      attr_accessor :env, :app, :result, :options

      # Public: create a new Batch Operation given the specifications for a batch
      # operation (as defined above) and the request environment for the main
      # batch request.
      def initialize(op, base_env, app)
        @op = op

        @method = op["method"] || "get"
        @url = op["url"]
        @params = op["params"] || {}
        @headers = op["headers"] || {}
        @options = op

        raise Errors::MalformedOperationError,
          "BatchAPI operation must include method (received #{@method.inspect}) " +
          "and url (received #{@url.inspect})" unless @method && @url

        @app = app
        # deep_dup to avoid unwanted changes across requests
        @env = BatchApi::Utils.deep_dup(base_env)
      end

      # Execute a batch request, returning a BatchResponse object.  If an error
      # occurs, it returns the same results as Rails would.
      def execute
        process_env
        begin
          response = @app.call(@env)
        rescue => err
          response = BatchApi::ErrorWrapper.new(err).render
        end
        response = BatchApi::Response.new(response)
        write_request_response_to_log(response)
        response
      end

      def write_request_response_to_log(response)
        #example log
        #I, [2018-02-01T18:05:00.213624 #96347]  INFO -- : get api/v2/patients/1000241/accessible_patients - - 401 {"errors":["No user with that authentication token exists"]}
        #custom format
        #method url params header status body
        #body conditional on a non 200 response
        log_hash = {}
        ["method", "url", "params", "headers"].each do |key|
          value = @op[key]
          if value
            if key == "headers"
              log_hash[key] = value["Authorization"]
            else
              if key == "params"
                ["password", "password_confirmation", "password_digest", "encrypted_password", "reset_password_token", "uuid"].each do |hash_key|
                  value[key] = "********"
                end
              end
              log_hash[key] = value
            end
          else
            log_hash[key] = "-"
          end
        end
        log_hash["status"] = response.status
        log_hash["body"] = response.body if response.status != 200
        BatchApi.logger.info log_hash
      end

      # Internal: customize the request environment.  This is currently done
      # manually and feels clunky and brittle, but is mostly likely fine, though
      # there are one or two environment parameters not yet adjusted.
      def process_env
        path, qs = @url.split("?")

        # Headers
        headrs = (@headers || {}).inject({}) do |heads, (k, v)|
          heads.tap {|h| h["HTTP_" + k.gsub(/\-/, "_").upcase] = v}
        end
        # preserve original headers unless explicitly overridden
        @env.merge!(headrs)

        # method
        @env["REQUEST_METHOD"] = @method.upcase

        # path and query string
        if @env["REQUEST_URI"]
          # not all servers provide REQUEST_URI -- Pow, for instance, doesn't
          @env["REQUEST_URI"] = @env["REQUEST_URI"].gsub(/#{BatchApi.config.endpoint}.*/, @url)
        end
        @env["REQUEST_PATH"] = path
        @env["ORIGINAL_FULLPATH"] = @env["PATH_INFO"] = @url

        @env["rack.request.query_string"] = qs
        @env["QUERY_STRING"] = qs

        # parameters
        @env["rack.request.form_hash"] = @params
        @env["rack.request.query_hash"] = @method == "get" ? @params : nil
      end
    end
  end
end
