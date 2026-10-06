# Content Security Policy to prevent XSS attacks
# Only applied if views are enabled, but good practice to define for API
if defined?(ActionView)
  Rails.application.config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self
    policy.img_src :self, :data, :https
    policy.font_src :self
    policy.object_src :none
  end
end
