class InvoiceImg < ActiveRecord::Base
  unloadable

  belongs_to :invoice
  validate :has_associated_invoice

  serialize :data

  def has_associated_invoice
    errors.add(:invoice) unless self.invoice and self.invoice.is_a? InvoiceDocument
  end

  after_create do
    update_invoice if data and tags
    if tags.any?
      Event.create(name: 'processed_pdf', invoice: invoice)
    else
      EventError.create(name: 'processed_pdf', invoice: invoice, notes: 'OCR failed')
    end
  end

  before_update do
    # TODO update invoice
  end

  def update_invoice
    if t=tags[:issue]
      invoice.date = text(t)
    end
    if t=tags[:due]
      invoice.due_date = text(t)
    end
    if t=tags[:subtotal]
      # Creates auxiliar line
      line = InvoiceLine.new(
        quantity: 1,
        description: 'Original invoice in PDF format',
        price: decimal(t)
      )
      invoice.invoice_lines << line
    end
    if t=tags[:tax_percentage] and invoice.invoice_lines.any?
      invoice.invoice_lines.each do |invoice_line|
        tax = Tax.new(
          name: 'IVA',
          percent: decimal(t)*100
        )
        invoice_line.taxes << tax
      end
    end
    if invoice.is_a? ReceivedInvoice
      invoice.state=:received
    else
      invoice.state=:new
    end
    invoice.client = fuzzy_match_client unless invoice.client
    invoice.save(validate: false)
    self.save
  end


  def tags
    return {} if data.nil?
    data[:tags] || {}
  end

  def useful_tokens
    useful = {}
    tokens.each do |number, attributes|
      if attributes[:text] and attributes[:text].size > 1
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
    return {} if data.nil?
    data[:tokens] || {}
  end

  def text(token)
    data[:tokens][token][:text] rescue nil
  end

  # "€600.00"
  # "18,00%"
  def decimal(token)
    cents = text(token).gsub(/\D/,'').to_i
    cents / 100.0
  rescue
    0
  end

  def width
    data['width']
  end

  def height
    data['height']
  end

  def fuzzy_match_client
    require 'fuzzy_match'
    match_tokens = tokens.collect do |k,v|
      v[:text].split(/\.|:/) if v[:text] =~ /\d/
    end.flatten.compact
    fm = FuzzyMatch.new(match_tokens, threshold: 0.6)
    best_client_match = nil
    best_text = nil
    best_score = 0.6
    invoice.company.project.clients.each do |client|
      text, score = fm.find_with_score(client.taxcode)
      if score and  score > best_score
        best_client_match = client
        best_score = score
        best_text = text
      end
    end
    if best_client_match
      tokens.each do |number, token|
        tags['seller_taxcode'] = number if token[:text].include?(best_text)
      end
    end
    company_match = fm.find(invoice.company.taxcode)
    if company_match
      tokens.each do |number, token|
        tags['buyer_taxcode'] = number if token[:text].include?(company_match)
      end
    end
    return best_client_match
  end

end
