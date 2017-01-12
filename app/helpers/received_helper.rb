module ReceivedHelper
  def invoice_imgs_context_menu(url)
    unless @context_menu_included
      content_for :header_tags do
        javascript_include_tag('invoice_imgs_context_menu', :plugin => 'haltr') +
          stylesheet_link_tag('context_menu')
      end
      if l(:direction) == 'rtl'
        content_for :header_tags do
          stylesheet_link_tag('context_menu_rtl')
        end
      end
      @context_menu_included = true
    end
    javascript_tag "contextMenuInit('#{ url_for(url) }')"
  end
  def invoice_img_tag_div(invoice_img, tag)
    reference = invoice_img.tags[tag]
    if reference.is_a? Array
      x = 0
      y = 0
      reference.each do |number|
        attributes = invoice_img.tokens[number.to_i]
        x = attributes[:x1].to_i if attributes[:x1].to_i > x
        y = attributes[:y0].to_i if attributes[:y0].to_i > y
      end
    else
      return if invoice_img.tokens[reference].nil?
      attributes = invoice_img.tokens[reference]
      x = attributes[:x1].to_i
      y = attributes[:y0].to_i
    end
    "<div class=\"rectangle-tag\" style=\"left:#{x+8}px; top:#{y}px;\">#{l("tag_#{tag}")}</div>".html_safe
  end
  def invoice_img_token_style(attributes)
    font_size = [attributes[:y1].to_i-attributes[:y0].to_i-1, 9].max
    font_size = 16 if font_size > 16
    "left:#{attributes[:x0].to_i-1}px; top:#{attributes[:y0].to_i-1}px; height:#{attributes[:y1].to_i-attributes[:y0].to_i+2}px; min-width:#{attributes[:x1].to_i-attributes[:x0].to_i+2}px; font-size:#{font_size}px; line-height: <%=font_size%>px;"
  end
end