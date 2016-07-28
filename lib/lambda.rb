require_relative '../../resource/lib/resource.rb'
class Lambda < Resource
  require_relative 'lambda/function'

  def initialize(*args)
    super(*args)
    @aws_client = Aws::Lambda::Client.new(region: @desired_properties[:region])
  end
end
