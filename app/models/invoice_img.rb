class InvoiceImg < ActiveRecord::Base

  belongs_to :invoice
  validate :has_associated_invoice

  serialize :data, Hash

  attr_protected :created_at, :updated_at

  def has_associated_invoice
    errors.add(:invoice) unless self.invoice and self.invoice.is_a? InvoiceDocument
  end

  after_initialize do
    if data.is_a? HashWithIndifferentAccess or Rails.env == 'test'
      # if data is a HashWithIndifferentAccess tranform to a Hash
      # ensure data keys are symbols and tag numbers are integers
      fix_datatypes
    end
  end

  after_create do
    update_invoice if data and tags
    if tags.any?
      Event.create(name: 'processed_pdf', invoice: invoice)
    else
      EventError.create(name: 'processed_pdf', invoice: invoice, notes: 'OCR failed')
    end
  end

  def fix_datatypes
    initial_data = data
    initial_tags = initial_data['tags'] || {}
    initial_tokens= initial_data['tokens'] || {}
    self.data = {}
    self.data[:tags] = {}
    self.data[:tokens] = {}
    self.data[:width] = initial_data['width']
    self.data[:height] = initial_data['height']
    self.data[:name] = initial_data['name']
    unless initial_data['currency'].blank?
      self.data[:currency] = initial_data['currency']
    end
    initial_tags.each do |tag, token_number|
      value = nil
      if token_number.is_a? Array
        value = []
        token_number.each do |num|
          value << num.to_i rescue token_number
        end
      else
        value = token_number.to_i rescue token_number
      end
      self.data[:tags][tag.to_sym] = value
    end
    initial_tokens.each do |token_number, token_data|
      token = {}
      token[:text] = token_data['text']
      token[:x0] = token_data['x0'].to_i
      token[:x1] = token_data['x1'].to_i
      token[:y0] = token_data['y0'].to_i
      token[:y1] = token_data['y1'].to_i
      self.data[:tokens][token_number.to_i] = token
    end
  end

  def update_invoice
    tags[:language]  = what_language unless tagv(:language)
    invoice.number   = tagv(:invoice_number).gsub(/\s/,'') rescue nil
    invoice.date     = input_date(tagv(:issue))
    invoice.due_date = input_date(tagv(:due))
    subtotal         = tagv(:subtotal).to_money rescue nil
    tax_percentage   = tagv(:tax_percentage).to_money rescue nil
    tax_amount       = tagv(:tax_amount).to_money rescue nil
    total            = tagv(:total).to_money rescue nil
    if tax_amount and total
      subtotal = total - tax_amount
    end
    if tax_percentage and total
      subtotal = total / ( 1 + tax_percentage.cents / 10000.0 )
    end
    if subtotal
      if invoice.invoice_lines.count == 1
        # Updates auxiliar line
        aux_line = invoice.invoice_lines.first
        aux_line.price = subtotal
        aux_line.save
      else
        # Creates auxiliar line
        aux_line = InvoiceLine.new(
          quantity: 1,
          description: 'Original invoice in PDF format',
          price: subtotal
        )
        invoice.invoice_lines << aux_line
      end
    end
    if tax_amount and !tax_percentage
      if subtotal != 0
        tax_percentage = tax_amount / subtotal * 100 rescue nil
      end
    end
    if tax_percentage and invoice.invoice_lines.any?
      invoice.invoice_lines.each do |invoice_line|
        if invoice_line.taxes.count == 1
          tax = invoice_line.taxes.first
          tax.percent = tax_percentage
          tax.save
        else
          tax = Tax.new(
            name: 'IVA',
            percent: tax_percentage
          )
          invoice_line.taxes << tax
        end
      end
      if tax_amount
        # TODO check tax_amount
      end
    end
    if invoice.is_a? ReceivedInvoice
      invoice.state=:received
    else
      invoice.state=:new
    end
    if !invoice.client
      if tagv(:seller_taxcode)
        invoice.client = invoice.company.project.clients.where(taxcode: tagv(:seller_taxcode).gsub(/\s/,'')).first
        if !invoice.client and  tagv(:seller_name)
          begin
            country_code = tagv(:seller_taxcode)[0..1] if tagv(:seller_taxcode)
            country_code = iso_country_from_text(tagv(:seller_country)) unless country_code and Valvat::Utils::EU_COUNTRIES.include?(country_code.upcase)
            new_client, client_office = Haltr::Utils.client_from_hash(
              project: invoice.project,
              name:    tagv(:seller_name),
              taxcode: tagv(:seller_taxcode),
              country: country_code.downcase,
              currency: currency,
              language: tags[:language]
            )
            invoice.client = new_client
            invoice.client_office = client_office
          rescue StandardError
            # client not OK
          end
        end
      end
    end
    invoice.client = fuzzy_match_client unless invoice.client
    invoice.currency = currency
    invoice.save(validate: false)
    self.save
  end

  def tagv(key)
    reference = tags[key]
    if reference.is_a? Array
      reference.collect do |ref|
        tokens[ref][:text]
      end.join(' ')
    else
      if tokens[reference]
        tokens[reference][:text]
      else
        reference
      end
    end
  rescue
    nil
  end

  def tags
    if data.is_a? Hash
      data[:tags]
    else
      raise "Data is a #{data.class}. Must be a Hash"
    end
  end

  def tags_inverted
    return @tags_inverted if @tags_inverted
    @tags_inverted = {}
    tags.each do |old_key,old_value|
      if old_value.is_a? Array
        old_value.each do |old_array_vaule|
          @tags_inverted[old_array_vaule]=old_key
        end
      else
          @tags_inverted[old_value]=old_key
      end
    end
    @tags_inverted
  end

  def useful_tokens
    useful = {}
    tokens.each do |number, attributes|
      if attributes[:text] and attributes[:text].gsub(/[^\w]/,'').size > 0
        useful[number] = attributes
        width =  attributes[:x1].to_i - attributes[:x0].to_i
        height = attributes[:y1].to_i - attributes[:y0].to_i
        if height > width
          # Rotate -90
          useful[number][:x1] = attributes[:x0].to_i + height
          useful[number][:y1] = attributes[:y0].to_i + width
        end
      end
    end
    return useful
  end

  def tokens
    data[:tokens]
  end

  def token_has_tag?(token)
    tags_inverted[token.to_i]
  end

  def text(token)
    data[:tokens][token.to_i][:text].gsub!("\t",' ') rescue nil
  end

  def width
    data[:width]
  end

  def height
    data[:height]
  end

  def currency
    data[:currency] || 'EUR'
  end

  def fuzzy_match_client
    require 'fuzzy_match'
    # Method #1 - fuzzy match against all tokens with numbers
    match_tokens = tokens.collect do |k,v|
      v[:text].gsub(/\.|:/,'') if v[:text] =~ /\d/
    end.flatten.compact
    fm = FuzzyMatch.new(match_tokens, threshold: 0.6)
    best_client_match = nil
    best_text = nil
    best_score = 0.6
    invoice.company.project.clients.each do |client|
      next if client.taxcode.blank?
      text, score = fm.find_with_score(client.taxcode)
      if score and  score > best_score
        best_client_match = client
        best_score = score
        best_text = text
      end
    end
    if best_client_match
      tokens.each do |number, token|
        tags[:seller_taxcode] = number if token[:text].include?(best_text)
      end
    else
      # Method #2 - join all text and look for an exact match
      #             finds client, but does not tag
      all_text = tokens.collect do |k,v|
        v[:text].gsub(/\.|:/,'')
      end.flatten.compact.join('').downcase
      invoice.company.project.clients.each do |client|
        next if client.taxcode.blank?
        if all_text.include?(client.taxcode.downcase)
          best_client_match = client
          break
        end
      end
    end
    # Try to tag our taxcode
    unless tags[:buyer_taxcode]
      company_match = fm.find(invoice.company.taxcode)
      if company_match
        tokens.each do |number, token|
          if token[:text].include?(company_match)
            tags[:buyer_taxcode] = number
          end
        end
      end
    end
    return best_client_match
  end

  def what_language
    require 'whatlanguage'
    invoice_string = tokens.collect do |k,v|
      v[:text] unless v[:text] =~ /\d/
    end.flatten.compact.join(' ')
    WhatLanguage.new.language_iso(invoice_string)
  end

  def iso_country_from_text(country_txt)
    begin
      fm = FuzzyMatch.new(ISO3166::Country.translations(tagv(:language)))
      # ["ES", "Espanya"]
      fm.find(country_txt)[0].downcase
    rescue
      invoice.company.country
    end
  end

  def input_date(d)
    return if d.nil?
    # Assume year 20xx. 16 -> 2016
    d.gsub(/([^\d])(\d\d)$/,"\\120\\2}")
    # "3 de mayo de 2014" -> "3 mayo 2014"
    d.gsub(' de ','')
  end

  def as_json(options)
    {
      id: self.invoice.id,
      tags: tags,
      tokens: tokens,
      width: width,
      height: height
    }
  end

  def all_possible_tags
    [:invoice_number, :language, :seller_country, :seller_name, :seller_taxcode, :buyer_taxcode, :issue, :due, :subtotal, :tax_percentage, :tax_amount,
     :tax_wh_percentage, :tax_wh_amount, :total]
  end

  def client?
    !invoice.client.nil?
  end

  def lines?
    invoice.invoice_lines.count > 0
  end

end
