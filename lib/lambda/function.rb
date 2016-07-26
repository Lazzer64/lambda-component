require 'digest'

class Resource
  class Lambda
    class Function < self
      METADATA = {
        function_name: [:key, :create],
        runtime: [:create, :update_config],
        handler: [:create, :update_config],
        role: [:create, :update_config],
        code: [:create, :update_code],
        description: [:update_config],
        timeout: [:update_config],
        memory_size: [:update_config],
        vpc_config: [:update_config],
        streams: [:update_triggers]
      }.freeze

      private

      def create_resource
        @wait_attempts = 100
        (0...@wait_attempts).each do
          begin
            resp = create_function
          rescue Aws::Lambda::Errors::InvalidParameterValueException
            sleep(@wait_time)
            next
          end
          return resp
        end
        raise Resource::ResourceTookToLong
      end

      def create_function
        @aws_client.create_function(
          function_name: @desired_properties[:function_name],
          runtime: @desired_properties[:runtime],
          handler: @desired_properties[:handler],
          role: @desired_properties[:role],
          code: {
            zip_file: File.read(@desired_properties[:code][:zip_file]),
            s3_bucket: @desired_properties[:code][:s3_bucket],
            s3_key: @desired_properties[:code][:s3_key],
            s3_object_version: @desired_properties[:code][:s3_object_version]
          }
        )
      end

      def delete_resource
        @aws_client.delete_function(function_name: @desired_properties[:function_name])
      end

      def raw_properties
        props = @aws_client.get_function_configuration(function_name: @desired_properties[:function_name]).to_h
        props[:event_source_mappings] = @aws_client.list_event_source_mappings(function_name: @desired_properties[:function_name]).event_source_mappings
        props
      rescue Aws::Lambda::Errors::ResourceNotFoundException
        nil
      end

      def parse_properties(raw_props)
        arns = []
        raw_props.delete(:event_source_mappings).each do |event|
          arn = @aws_client.get_event_source_mapping(uuid: event.uuid).event_source_arn
          arns[arns.length] = arn
        end
        raw_props[:streams] = arns
        Resource::Properties.new(self.class, raw_props)
      end

      def update_code(code)
        # TODO code from s3
        unless code[:zip_file].nil?
          zip = File.read(code[:zip_file])
          @aws_client.update_function_code(
            function_name: @desired_properties[:function_name],
            zip_file: zip
          )
        end
      end

      def same_code?(code, current)
        # TODO code from s3
        return false if code.nil?
        unless code[:zip_file].nil?
          zip = File.read(code[:zip_file])
          sha = Digest::SHA256.base64digest(zip) 
          sha == current[:code_sha_256]
        end
      end

      def format_diff!(diff)
        diff.delete(:code) if same_code?(diff[:code], properties?) 
        diff
      end

      def create_event_source(arn)
        @aws_client.create_event_source_mapping({
          event_source_arn: arn,
          function_name: @desired_properties[:function_name],
          starting_position: "TRIM_HORIZON",
        })
      end

      def update_streams(streams)
        streams.each do |stream_arn|
          # TODO wait for stream to be ready
          @aws_client.create_event_source_mapping(
            event_source_arn: stream_arn, 
            function_name: @desired_properties[:function_name], 
            starting_position: 'TRIM_HORIZON'
          )        
        end
      end

      def process_diff(diff)
        diff.each do |key, val|
          update_streams(val) if keys(:update_triggers).include?(key)
          update_code(diff[:code]) if keys(:update_code).include?(key)
          if keys(:update_config).include?(key)
            @aws_client.update_function_configuration(
              :function_name => @desired_properties[:function_name],
              key => val
            )
          end
          next
        end
      end
    end
  end
end
