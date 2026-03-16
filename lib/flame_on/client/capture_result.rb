module FlameOn
  module Client
    CaptureResult = Struct.new(:value, :trace, keyword_init: true)
  end
end
