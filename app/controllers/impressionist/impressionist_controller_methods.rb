require 'digest/sha2'

module Impressionist
  module ImpressionistControllerMethods
  extend ActiveSupport::Concern

  included do
    before_filter :impressionist_app_filter
  end

  module ClassMethods
    def impressionist(opts={})
      before_filter { |c| c.impressionist_subapp_filter(opts[:actions], opts[:unique])}
    end
  end

  def impressionist(impressionable,message=nil,opts={})
    unless bypass_impression?
      if impressionable.respond_to?(:impressionable?)
        if unique_impressionable_impression?(impressionable, opts[:unique])
          impressionable.impressions.create(associative_impression_attributes({:message => message}))
        end
      else
        # we could create an impression anyway. for classes, too. why not?
        raise "#{impressionable.class.to_s} is not impressionable!"
      end
    end
  end

  def impressionist_app_filter
    @impressionist_hash = Digest::SHA2.hexdigest(Time.now.to_f.to_s+rand(10000).to_s)
  end

  def impressionist_subapp_filter(actions=nil,unique_opts=nil)
    unless bypass_impression
      actions.collect!{|a|a.to_s} unless actions.blank?
      if (actions.blank? || actions.include?(action_name)) && unique_impression?(unique_opts)
        Impression.create(direct_impression_attributes)
      end
    end
  end

  private

  def bypass_impression?
    Impressionist::Bots::WILD_CARDS.each do |wild_card|
      return true if request.user_agent and request.user_agent.downcase.include? wild_card
    end
    Impressionist::Bots::LIST.include? request.user_agent
  end

  def unique_impressionable_impression?(impressionable, unique_opts)
    return unique_opts.blank? || !impressionable.impressions.where(unique_impression_query(unique_opts)).exists?
  end

  def unique_impression?(unique_opts)
    return unique_opts.blank? || !Impression.where(unique_impression_query(unique_opts)).exists?
  end

  # creates the query to check for uniqueness
  def unique_impression_query(unique_opts)
    full_statement = direct_impression_attributes
    # reduce the full statement to the params we need for the specified unique options
    unique_opts.reduce({}) do |query, param|
      query[param] = full_statement[param]
      query
    end
  end

  # creates a statment hash that contains default values for creating an impression via an AR relation.
  def associative_impression_attributes(query_params={})
    query_params.reverse_merge!(
      :controller_name => controller_name,
      :action_name => action_name,
      :user_id => user_id_for_impression,
      :request_hash => @impressionist_hash,
      :session_hash => session_hash,
      :ip_address => request.remote_ip,
      :referrer => request.referer
      )
  end

  # creates a statment hash that contains default values for creating an impression.
  def direct_impression_attributes(query_params={})
    query_params.reverse_merge!(
      :impressionable_type => controller_name.singularize.camelize,
      :impressionable_id=> params[:id]
      )
    associative_impression_attributes(query_params)
  end

  def session_hash
    # # careful: request.session_options[:id] encoding in rspec test was ASCII-8BIT
    # # that broke the database query for uniqueness. not sure if this is a testing only issue.
    # str = request.session_options[:id]
    # logger.debug "Encoding: #{str.encoding.inspect}"
    # # request.session_options[:id].encode("ISO-8859-1")
    request.session_options[:id]
  end

  #use both @current_user and current_user helper
  def user_id_for_impression
    user_id = @current_user ? @current_user.id : nil rescue nil
    user_id = current_user ? current_user.id : nil rescue nil if user_id.blank?
    user_id
  end
end

end