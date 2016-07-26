require_relative '../../resource/lib/resource.rb'
class Resource
  class Lambda < self
    require_relative 'lambda/function'

    def initialize(*args)
      super(*args)
      @aws_client = Aws::Lambda::Client.new(region: @desired_properties[:region])
    end
  end
end
