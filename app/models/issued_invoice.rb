class IssuedInvoice < InvoiceDocument

  has_one :created_invoice, class_name: 'ReceivedInvoice',
    foreign_key: 'created_from_invoice_id'

  include Haltr::ExportableDocument

  belongs_to :invoice_template
  validates_presence_of :number, :unless => Proc.new {|invoice| invoice.type == "DraftInvoice"}
  validate :number_must_be_uniq
  validate :invoice_must_have_lines

  before_validation :set_due_date
  before_save :update_imports, :unless => Proc.new {|i| i.changed_attributes.keys == ['state'] }
  after_create :create_event
  after_destroy :release_amended
  before_save :update_status, :unless => Proc.new {|invoicedoc| invoicedoc.state_changed? }
  before_save :set_state_updated_at
  before_save :override_line_values, :unless => Proc.new {|i| i.new_record? }

  def has_been_sent?
    sent? or closed? or sending?
  end

  def label
    if self.amend_of or self.amended_number
      l :label_amendment_invoice
    else
      l :label_invoice
    end
  end

  def number_must_be_uniq
    if type == "IssuedInvoice"
      if series_code.blank?
        series_code_value = ["", nil]
      else
        series_code_value = series_code
      end
      query = IssuedInvoice.where(project_id: project, number: number, series_code: series_code_value)
      query = query.where(["YEAR(date) = ?", date.year]) unless date.nil?
      query = query.where(["id != ?", id]) unless new_record?
      if query.any?
        if date.nil?
          errors.add(:number, :taken)
        else
          errors.add(:number, l(:number_taken_in_year, number: number, year: date.year))
        end
      end
    end
  end

  def self.find_can_be_sent(project)
    invoices = project.issued_invoices.includes(:client).references(:client).where(
      "state='new' and " +
      "date <= ? and clients.invoice_format in (?)",
      Date.today,
      ExportChannels.can_send.keys
    ).order(id: :asc, number: :asc)
    invoices_extra_filter = Redmine::Hook.call_hook(
      :model_invoice_can_be_sent_additional_filters, :invoices => invoices
    )
    invoices_extra_filter.any? ? invoices_extra_filter.first : invoices
  end

  def self.find_not_sent(project)
    project.issued_invoices.where("state='new' and number is not null")
  end

  def self.candidates_for_payment(payment)
    # order => older invoices to get paid first
    where(
      "project_id = ? and total_in_cents = ? and date <= ? and state != 'closed'",
      payment.project_id,
      payment.amount_in_cents,
      payment.date
    ).order("due_date ASC")
  end

  def past_due?
    !closed? && due_date && due_date < Date.today
  end

  def self.past_due_total(project)
    IssuedInvoice.sum :total_in_cents, :conditions => ["state <> 'closed' and due_date < ? and project_id = ?", Date.today, project.id]
  end

  def self.last_number(project)
    # assume invoices with > date will have > number
    numbers = project.issued_invoices.order("date DESC, created_at DESC").limit(10).collect {|i|
      i.number
    }.compact
    numbers.sort_by do |num|
      # invoices_001 -> [1,   "invoices_001"]
      # i7           -> [7,   "i7"]
      # 2014/i8      -> [2014, 8, "2014/i8"]
      # 08/001       -> [8,    1, "08/001"]
      num.scan(/\d+/).collect{|i|i.to_i} + [num]
    end.last
  rescue
    ""
  end

  def self.next_number(project)
    number = self.last_number(project)
    self.increment_right(number)
  end

  def self.increment_right(number)
    return "1" if number.nil?
    nums = number.scan(/\d+/).size
    digits = number.scan(/\d+/).last.to_s.size
    return "#{number}1" if nums == 0
    i = 0
    number.gsub(/(\d+)/) do |m|
      i += 1
      if i == nums
        m = sprintf("%0#{digits}d", m.to_i+1)
      else
        m
      end
    end
  end

  def visible_by_client?
    !%w(new sending processing_pdf discarded).include? state
  end

  # returns true if invoice has been totally amended (substituted by another)
  def amended?
    (!self.amend_id.nil? and self.amend_id != self.id )
  end

  # all amends, sustitutive and partial
  def is_amend?
    amend_of or partial_amend_of or amended_number
  end

  def last_sent_event
    events.where(name: 'success_sending').first
  end

  def local_cert_js
    "doSign('/invoices/base64doc/#{id}/','#{ExportChannels.format(client.invoice_format)}')"
  end

  def valid?(context = nil)
    # do not validate invoices with original PDF, only check for client #6334
    if original and invoice_format == 'pdf'
      if client.nil?
        errors.add(:client, :blank)
        return false
      else
        true
      end
    else
      super
    end
  end

  protected

  # called after_create (only NEW invoices)
  def create_event
    if self.original
      event = EventWithFile.new(:name=>self.transport,:invoice=>self,
                                :user=>User.current,:file=>self.original,
                                :filename=>self.file_name)
    else
      event = Event.new(:name=>(self.transport||'new'),:invoice=>self,:user=>User.current)
    end
    event.audits = self.last_audits_without_event
    event.save!
  end

  def release_amended
    if self.amend_of
      self.amend_of.amend_id = nil
      self.amend_of.save
    end
  end

  def update_status
    update_imports
    if is_paid?
      if may_paid?
        update_attribute(:state, :closed)
        Event.create(name: 'paid', invoice: self, user: User.current)
      end
    else
      if closed?
        update_attribute(:state, :sent)
        Event.create(name: 'unpaid', invoice: self, user: User.current)
      end
    end
    return true # always continue saving
  end

  # if state changes, record state timestamp :state_updated_at
  # an update to an Invoice sets timestamps as usual, except for:
  #  :state
  #  :has_been_read
  #  :state_updated_at
  # these attributes do not change updated_at
  def set_state_updated_at
    if state_changed?
      write_attribute :state_updated_at, Time.now
    end
  end

  def override_line_values
    if ponumber_changed?
      invoice_lines.each do |l|
        l.ponumber = ponumber
      end
    end
    if file_reference_changed?
      invoice_lines.each do |l|
        l.file_reference = file_reference
      end
    end
    if receiver_contract_reference_changed?
      invoice_lines.each do |l|
        l.receiver_contract_reference = receiver_contract_reference
      end
    end
  end

end
