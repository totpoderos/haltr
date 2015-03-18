class ExportChannels 

  unloadable

  def self.available
    # See config/channels.yml.example
    @@channels ||= File.read(File.join(File.dirname(__FILE__), "../../config/channels.yml"))
    YAML.load(@@channels)
  rescue Exception => e
    puts "Exception while retrieving channels.yml: #{e.message}"
    {}
  end

  def self.permissions
    channel_permissions = {}
    self.available.values.each do |channel|
      channel["allowed_permissions"].each do |permission,actions|
        channel_permissions[permission] ||= {}
        channel_permissions[permission].merge!(actions) if actions
      end
    end
    channel_permissions
  end

  def self.default
    'signed_pdf'
  end

  def self.available?(id)
    available.include? id
  end

  def self.format(id)
    available[id]["format"] if available? id
  end

  def self.folder(id)
    available[id]["folder"] if available? id
  end

  def self.class_for_send(id)
    available[id]["class_for_send"] if available? id
  end

  def self.options(id)
    available[id]["options"] if available? id
  end

  def self.validations(id)
    validations = [:allowed_to_send_this_state]
    return validations if available[id].nil?
    unless available[id]["validate"].nil?
      validations += available[id]["validate"].is_a?(Array) ? available[id]["validate"] : [available[id]["validate"]]
    end
    validations += ExportFormats.validations(available[id]["format"]) if available[id]["format"]
    validations.compact.uniq
  end

  def self.for_select(current_project)
    available.sort { |a,b|
      if a[1]['order'].blank? and b[1]['order'].blank?
        a[0].downcase <=> b[0].downcase
      elsif a[1]['order'].blank?
        1
      elsif b[1]['order'].blank?
        -1
      else
        a[1]['order'].to_i <=> b[1]['order'].to_i
      end
    }.collect {|k,v|
      unless User.current.admin?
        allowed = false
        v["allowed_permissions"].each_key do |perm|
          allowed = true if User.current.allowed_to?(perm, current_project)
        end
        next unless allowed
      end
      [ v["locales"][I18n.locale.to_s], k ]
    }.compact
  end

  def self.path(id)
    "#{Setting.plugin_haltr['export_channels_path']}/#{self.folder(id)}"
  end

  def self.l(channel_name)
    available[channel_name]['locales'][I18n.locale.to_s] rescue ''
  end

  def self.[](id)
    available[id]
  end

  def self.punts_generals
    available.collect {|k,v|
      k if v["locales"]["ca"] =~ /punt general/i
    }.compact
  end

end

