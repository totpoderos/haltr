class ExportChannelsController < ApplicationController


  layout 'admin'
  menu_item :export_channels
  before_filter :authorize_global
  helper :haltr

  def index
    @channels = ExportChannels.available.sort do |a,b|
      if a[1]['order'].blank? and b[1]['order'].blank?
        a[0].casecmp(b[0])
      elsif a[1]['order'].blank?
        1
      elsif b[1]['order'].blank?
        -1
      else
        a[1]['order'].to_i <=> b[1]['order'].to_i
      end
    end
  end

end
