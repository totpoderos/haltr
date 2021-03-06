# encoding: utf-8
require File.expand_path('../../test_helper', __FILE__)

class InvoiceTest < ActiveSupport::TestCase

  fixtures :clients, :invoices, :invoice_lines, :taxes, :companies, :people, :bank_infos, :dir3_entities, :external_companies, :client_offices

  def setup
    User.current=nil
    Haltr::TestHelper.fix_invoice_totals
  end

  test "next and previous invoice in project context" do
    i = invoices(:i5)
    assert_equal 'i6', i.next.number
    assert_equal 'i4', i.previous.number
    i = invoices(:invoices_001) # id = 1
    assert_nil i.previous
  end

  test "due dates" do
    date = Date.new(2000,12,1)
    i = IssuedInvoice.new(:client=>clients(:client1),:project=>Project.find(2),:date=>date,:number=>111)
    i.invoice_lines << invoice_lines(:invoice1_l1).dup
    i.invoice_lines.each do |line|
      line.taxes = [Tax.new(name: 'VAT', percent: 0, category: 'E')]
    end
    i.save!
    assert_equal date, i.due_date
    i = IssuedInvoice.new(:client=>clients(:client1),:project=>Project.find(2),:date=>date,:number=>222,:terms=>"1m15")
    i.invoice_lines << invoice_lines(:invoice1_l1).dup
    i.invoice_lines.each do |line|
      line.taxes = [Tax.new(name: 'VAT', percent: 0, category: 'E')]
    end
    i.save!
    assert_equal Date.new(2001,1,15), i.due_date
    i = IssuedInvoice.new(:client=>clients(:client1),:project=>Project.find(2),:date=>date,:number=>333,:terms=>"3m15")
    i.invoice_lines << invoice_lines(:invoice1_l1).dup
    i.invoice_lines.each do |line|
      line.taxes = [Tax.new(name: 'VAT', percent: 0, category: 'E')]
    end
    i.save!
    assert_equal Date.new(2001,3,15), i.due_date
  end

  test "do not modify due dates on save" do
    i = invoices(:invoice1)
    d = Date.new(2010,1,1)
    i.due_date = d
    i.save!
    i = Invoice.find i.id
    assert_equal Date.new(2008,12,1), i.due_date
  end

  test "invoice number increment right" do
    assert_equal "not_an_i1", IssuedInvoice.increment_right("not_an_i")
    assert_equal "1", IssuedInvoice.increment_right(nil)
    assert_equal "2011/2", IssuedInvoice.increment_right("2011/1")
    assert_equal "2011-2", IssuedInvoice.increment_right("2011-1")
    assert_equal "11/002", IssuedInvoice.increment_right("11/001")
    assert_equal "0032", IssuedInvoice.increment_right("0031")
    assert_equal "1000", IssuedInvoice.increment_right("999")
  end

  test "sort draft invoices" do
    assert_equal(-1 , invoices(:draft) <=> invoices(:invoice1))
    assert_equal 1 , invoices(:invoice1) <=> invoices(:draft)
    assert_equal 0 , invoices(:draft) <=> invoices(:draft)
  end

  test "invoice contable validation" do
    assert_equal 100, invoices(:invoices_003).subtotal_without_discount.dollars
    assert_equal 100, invoices(:invoices_003).taxable_base.dollars
    assert_equal 18, invoices(:invoices_003).tax_amount.dollars
    assert_equal 1, invoices(:invoices_003).taxes_uniq.size
    assert_equal 100, invoices(:invoices_003).subtotal.dollars
    assert_equal 0, invoices(:invoices_003).discount_amount.dollars
    assert_equal 118, invoices(:invoices_003).total.dollars

    assert_equal 100, invoices(:invoices_002).subtotal_without_discount.dollars
    assert_equal 85, invoices(:invoices_002).taxable_base.dollars
    assert_equal 15.30, invoices(:invoices_002).tax_amount.dollars
    assert_equal 1, invoices(:invoices_002).taxes_uniq.size
    assert_equal 85, invoices(:invoices_002).subtotal.dollars
    assert_equal 15, invoices(:invoices_002).discount_amount.dollars
    assert_equal 100.30, invoices(:invoices_002).total.dollars

    assert_equal 250, invoices(:invoices_001).subtotal_without_discount.dollars
    assert_equal 225, invoices(:invoices_001).taxable_base.dollars
    assert_equal 2.7, invoices(:invoices_001).tax_amount.dollars
    assert_equal(-13.5, invoices(:invoices_001).tax_amount(taxes(:taxes_006)).dollars)
    assert_equal 16.2, invoices(:invoices_001).tax_amount(taxes(:taxes_005)).dollars
    assert_equal 7.2, invoices(:invoices_001).tax_amount(taxes(:taxes_007)).dollars
    assert_equal(-7.2, invoices(:invoices_001).tax_amount(taxes(:taxes_008)).dollars)
    assert_equal 4, invoices(:invoices_001).taxes_uniq.size
    assert_equal 225, invoices(:invoices_001).subtotal.dollars
    assert_equal 25, invoices(:invoices_001).discount_amount.dollars
    assert_equal 227.7, invoices(:invoices_001).total.dollars
  end

  test "currency to upcase" do
    i=invoices(:invoices_003)
    assert_equal "EUR", i.currency
    i.currency="usd"
    assert_equal "USD", i.currency
  end

  test "taxes_by_category" do
    i=invoices(:i5)
    categories = i.taxes_by_category
    assert_equal 1, categories.size
    assert_equal 1, categories["VAT"].size
    assert categories["VAT"]["E"]
  end

  test "taxes_without_company_tax" do
    i = invoices(:i5)
    c = companies(:company1)
    assert_equal 1, i.taxes.size
    line = i.invoice_lines.first
    line.taxes << Tax.new(:company => nil, :invoice_line => line, :name => 'VAT', :percent => 99.0, :category => 'XL', :comment => 'This is unique to this invoice line. Company does not have a tax like this.')
    line.save!
    assert_equal 2, i.taxes.size
    assert_equal 4, c.taxes.size
    # invoice i5 and company share one tax, so 2 + 4 - 1 = 5
    assert_equal(5, i.available_taxes.size)
  end

  test "to string" do
    i = invoices(:i7)
    assert i.to_s.split.size > 1
  end

  test "invoice_taxable_base_with_exempts_and_zeros" do
    i = invoices(:i7)
    assert_equal 2, i.invoice_lines.size
    i.invoice_lines[0].taxes = [ Tax.new(:code=>"0.0_E",:name=>"VAT") ]
    i.invoice_lines[1].taxes = [ Tax.new(:code=>"0.0_Z",:name=>"VAT") ]
    i.save
    assert_equal 1, i.invoice_lines[0].taxes.size
    assert_equal 1, i.invoice_lines[1].taxes.size
    assert_equal i.invoice_lines[0].total_cost, i.taxable_base(Tax.new(:code=>"0.0_E",:name=>"VAT")).dollars
    assert_equal i.invoice_lines[1].total_cost,  i.taxable_base(Tax.new(:code=>"0.0_Z",:name=>"VAT")).dollars
  end

  test "invoice check tax_per_line? method" do
    i = invoices(:i7)
    assert i.tax_per_line?('VAT')
    i.taxes.each do |tax|
      tax.code = "20.0_S"
      tax.save
    end
    assert_equal false, i.tax_per_line?('VAT')
  end

  test "recipient_emails returns a hash of email addresses" do
    i = invoices(:i7)
    assert i.recipient_emails
  end

  test 'only people with send_invoices_by_mail are included' do
    # i7 -> client_001 -> person1
    i = invoices(:i7)
    # recipient_emails contains also the client's main email
    assert_equal 2, i.recipient_emails.count
    assert_equal 'person1@example.com', i.recipient_emails.first
  end

  test 'payment_method_requirements' do
    # invoice with payment cash (no requirements)
    i = invoices(:i8)
    assert(i.valid?)
    # invoice with payment debit (client has bank_account)
    i = invoices(:i9)
    assert(i.valid?)
    # remove client bank_account
    i.client.bank_account = ""
    assert(i.valid?)
    i.about_to_be_sent=true
    assert(!i.valid?)
    assert(i.errors.messages.keys.include?(:payment_method))
    # invoice with payment transfer (invoice has bank_info)
    i = invoices(:i7)
    assert_not_nil i.bank_info
    assert(i.valid?)
    i.bank_info = nil
    assert(i.valid?)
    i.about_to_be_sent=true
    assert(!i.valid?)
    assert(i.errors.messages.keys.include?(:payment_method))
  end

  test 'invoice_has_taxes' do
    i = invoices(:i8)
    assert(i.valid?)
    assert_equal(0, i.errors.size)
    i.invoice_lines.first.taxes=[]
    assert(i.valid?) # facturae errors expected to be checked only when sending
    i.about_to_be_sent=true
    assert(!i.valid?)
    assert_equal(1, i.errors.size)
  end

  test 'invoice payment_method' do
    i = invoices(:i8)
    assert_equal(Invoice::PAYMENT_CASH, i.payment_method)
    assert_nil i.bank_info
    i.payment_method = "#{Invoice::PAYMENT_TRANSFER}_1"
    assert i.transfer?
    assert_equal(bank_infos(:bi1),i.bank_info)
    assert i.valid?
    i.payment_method = "#{Invoice::PAYMENT_TRANSFER}_2"
    assert !i.valid?, "bank_info is from other company"
    i.payment_method = Invoice::PAYMENT_TRANSFER
    assert i.valid?
    i.about_to_be_sent=true
    assert !i.valid?
    assert i.transfer?
    assert_nil i.bank_info
    i.payment_method = "#{Invoice::PAYMENT_DEBIT}_1"
    assert i.debit?, "invoice payment is debit"
    assert_equal(i.bank_info,bank_infos(:bi1))
    assert i.valid?
  end

  # import invoice_facturae32_signed.xml
  test 'create received_invoice from facturae32' do
    # client does not exist
    assert_nil Client.find_by_taxcode "ESP1700000A"
    # and there's no external company
    assert_nil ExternalCompany.find_by_taxcode "ESP1700000A"
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_signed.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company1),"1234",'uploaded',User.current.name)
    client  = Client.find_by_taxcode "ESP1700000A"
    assert_not_nil client
    # client
    assert_equal "ESP1700000A", client.taxcode
    assert_equal "Ingent-lluís", client.name
    assert_equal "Melió 113", client.address
    assert_equal "Barcelona", client.province
    assert_equal "tr", client.country
    assert_equal "", client.website
    assert_equal "ESP6611111C@b2brouter.net", client.email
    assert_equal "08720", client.postalcode
    assert_equal "Vilafranca", client.city
    assert_equal "EUR", client.currency
    assert_equal invoice.company.project, client.project
    # invoice
    assert       invoice.is_a?(ReceivedInvoice)
    assert_equal client, invoice.client
    assert_equal companies(:company1), invoice.company
    assert_equal "766", invoice.number
    assert_equal "2012-04-20", invoice.date.to_s
    assert_equal 658.00, invoice.total.to_f
    assert_equal 600.00, invoice.import.to_f
    assert_equal "2012-06-01", invoice.due_date.to_s
    assert_equal "EUR", invoice.currency
    assert_equal "facturae32", invoice.invoice_format
    assert_equal "uploaded", invoice.transport
    assert_equal "Anonymous", invoice.from
    assert_equal "1234", invoice.md5
    assert_equal "20120420_invoice_facturae32_signed.xml", invoice.file_name
    # invoice lines
    assert_equal 3, invoice.invoice_lines.size
    assert_equal 600.00, invoice.invoice_lines.collect {|l| l.quantity*l.price }.sum.to_f
    invoice.invoice_lines.each do |il|
      assert_equal 100, il.price
      assert_equal 1, il.taxes.size
      assert_equal 'IVA', il.taxes.first.name
    end
    assert_equal 1, invoice.invoice_lines[0].quantity
    assert_equal 2, invoice.invoice_lines[1].quantity
    assert_equal 3, invoice.invoice_lines[2].quantity
    # taxes
    assert_equal 18.0, invoice.invoice_lines[0].taxes[0].percent
    assert_equal 8.0,  invoice.invoice_lines[1].taxes[0].percent
    assert_equal 8.0,  invoice.invoice_lines[2].taxes[0].percent
    assert_equal 'S',  invoice.invoice_lines[0].taxes[0].category
    assert_equal 'S',  invoice.invoice_lines[1].taxes[0].category
    assert_equal 'S',  invoice.invoice_lines[2].taxes[0].category
  end

  # import invoice_facturae32_issued.xml
  test 'create issued_invoice from facturae32' do
    # client does not exist
    assert_nil Client.find_by_taxcode "ESP1700000A"
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued.xml'))
    assert_nil(Client.find_by_taxcode "ESP1700000A")
    invoice = Invoice.create_from_xml(file,companies(:company1),"1234",'uploaded',User.current.name)
    client  = Client.find_by_taxcode "ESP1700000A"
    assert_not_nil client
    default_channel = 'paper'
    if ExportChannels.available.include? 'link_to_pdf_by_mail'
      default_channel = 'link_to_pdf_by_mail'
    end
    # client
    assert_equal "ESP1700000A", client.taxcode
    assert_equal "David Copperfield", client.name
    assert_equal "Address1", client.address
    assert_equal "state", client.province
    assert_equal "es", client.country
    assert_nil   client.website
    assert_equal "suport@ingent.net", client.email
    assert_equal "08720", client.postalcode
    assert_equal "city", client.city
    assert_equal "EUR", client.currency
    assert_equal invoice.company.project, client.project
    assert_equal "ES8023100001180000012345", client.iban
    assert_equal "biiiiiiiiic", client.bic
    assert_equal default_channel, client.invoice_format
    # invoice
    assert       invoice.is_a?(IssuedInvoice)
    assert_equal client, invoice.client
    assert_equal companies(:company1), invoice.company
    assert_equal "767", invoice.number
    assert_equal "2012-04-20", invoice.date.to_s
    assert_equal 671.00, invoice.total.to_f
    assert_equal 600.00, invoice.import.to_f
    assert_equal "2012-06-01", invoice.due_date.to_s
    assert_equal "EUR", invoice.currency
    assert_equal "facturae32", invoice.invoice_format
    assert_equal "uploaded", invoice.transport
    assert_equal "Anonymous", invoice.from
    assert_equal "1234", invoice.md5
    assert invoice.debit?, "invoice payment is debit"
    assert_equal '2_4', invoice.payment_method
    assert_equal "invoice_facturae32_issued.xml", invoice.file_name
    # invoice lines
    assert_equal 3, invoice.invoice_lines.size
    assert_equal 600.00, invoice.invoice_lines.collect {|l| l.quantity*l.price }.sum.to_f
    invoice.invoice_lines.each do |il|
      assert_equal 100, il.price
      assert_equal 1, il.taxes.size
      assert_equal 'IVA', il.taxes.first.name
    end
    assert_equal 1, invoice.invoice_lines[0].quantity
    assert_equal 2, invoice.invoice_lines[1].quantity
    assert_equal 3, invoice.invoice_lines[2].quantity
    # taxes
    assert_equal 21.0, invoice.invoice_lines[0].taxes[0].percent
    assert_equal 10.0, invoice.invoice_lines[1].taxes[0].percent
    assert_equal 10.0, invoice.invoice_lines[2].taxes[0].percent
    assert_equal 'S',  invoice.invoice_lines[0].taxes[0].category
    assert_equal 'AA', invoice.invoice_lines[1].taxes[0].category
    assert_equal 'AA', invoice.invoice_lines[2].taxes[0].category
  end

  # import invoice_facturae32_issued2.xml
  test 'create issued_invoice from facturae32 with irpf, discount, bank_account and existing client' do
    client = Client.find_by_taxcode "A13585625"
    assert_nil client.company # not linked
    client_count = Client.count
    # client exists
    assert_not_nil client
    assert_equal "1233333333333333", client.bank_account
    client_last_changed = client.updated_at
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued2.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company1),"1234",'uploaded',User.current.name)
    assert_equal client_last_changed, client.updated_at
    assert_equal client_count, Client.count
    # invoice
    assert       invoice.is_a?(IssuedInvoice)
    assert_equal client, invoice.client
    assert_equal companies(:company1), invoice.company
    assert_equal "i10", invoice.number
    assert_equal "2013-12-13", invoice.date.to_s
    assert_equal 90.78, invoice.total.to_f
    assert_equal 102.00, invoice.import.to_f
    assert_equal "2014-01-31", invoice.due_date.to_s
    assert_equal "USD", invoice.currency
    assert_equal "facturae32", invoice.invoice_format
    assert_equal "uploaded", invoice.transport
    assert_equal "Anonymous", invoice.from
    assert_equal "1234", invoice.md5
    assert_equal "invoice_facturae32_issued2.xml", invoice.file_name
    assert_equal 15, invoice.discount_percent
    assert_equal 18.00, invoice.discount_amount.to_f
    assert_equal "promo", invoice.discount_text
    assert_equal "invoice notes", invoice.extra_info
    assert invoice.debit?, "invoice payment is debit"
    assert_equal "1233333333333333", invoice.client.bank_account
    assert_equal bank_infos(:bi4), invoice.bank_info
    # invoice lines
    assert_equal 1, invoice.invoice_lines.size
    il = invoice.invoice_lines.first
    assert_equal 0.8,    il.price
    assert_equal 150,    il.quantity
    # taxes
    assert_equal 2,      il.taxes.size
    assert_equal 'IVA',  il.taxes[1].name
    assert_equal 10.0,   il.taxes[1].percent
    assert_equal 'AA',   il.taxes[1].category
    assert_equal 'IRPF', il.taxes[0].name
    assert_equal(-21.0,  il.taxes[0].percent)
    assert_equal 'S',    il.taxes[0].category
    # email override lluis@ingent.net, instead of client1@email.com
    assert_equal 'lluis@ingent.net', invoice.client_email_override
    # company email override
    assert_equal 'override@companymail.net', invoice.company_email_override
  end

  # import invoice_facturae32_issued3.xml
  test 'create issued_invoice from facturae32 with charge, different taxes per line and accounting_cost' do
    client = Client.find_by_taxcode "A13585625"
    client_count = Client.count
    # client exists
    assert_not_nil client
    assert_equal "1233333333333333", client.bank_account
    client_last_changed = client.updated_at
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued3.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company1),"1234",'uploaded',User.current.name)
    assert_equal client_last_changed, client.updated_at
    assert_equal client_count, Client.count
    # invoice
    assert       invoice.is_a?(IssuedInvoice)
    assert_equal client, invoice.client
    assert_equal companies(:company1), invoice.company
    assert_equal "100336", invoice.number
    assert_equal "2014-01-09", invoice.date.to_s
    assert_equal 122.10, invoice.total.to_f
    assert_equal 120.00, invoice.import.to_f
    assert_equal "2014-02-08", invoice.due_date.to_s
    assert_equal "EUR", invoice.currency
    assert_equal "facturae32", invoice.invoice_format
    assert_equal "uploaded", invoice.transport
    assert_equal "Anonymous", invoice.from
    assert_equal "1234", invoice.md5
    assert_equal "invoice_facturae32_issued3.xml", invoice.file_name
    assert invoice.cash?, "invoice payment should be cash and is #{invoice.payment_method}"
    assert_equal "1233333333333333", invoice.client.bank_account
    assert_nil invoice.bank_info
    assert_equal 100.00, invoice.charge_amount.dollars
    assert_equal "paid in clients name", invoice.charge_reason
    assert_equal "23", invoice.accounting_cost
    # invoice lines
    assert_equal 2, invoice.invoice_lines.size
    il = invoice.invoice_lines.first
    assert_equal 10,          il.price
    assert_equal 1,           il.quantity
    assert_equal "with0iva",  il.description
    assert_equal 1,           il.taxes.size
    assert_equal 'IVA',       il.taxes[0].name
    assert_equal 0.0,         il.taxes[0].percent
    assert_equal 'Z',         il.taxes[0].category
    il = invoice.invoice_lines.last
    assert_equal 10,          il.price
    assert_equal 1,           il.quantity
    assert_equal "with21iva", il.description
    assert_equal 1,           il.taxes.size
    assert_equal 'IVA',       il.taxes[0].name
    assert_equal 21.0,        il.taxes[0].percent
    assert_equal 'S',         il.taxes[0].category
    # events
    assert_equal 1,        invoice.events.size
    assert_equal "uploaded", invoice.events.first.name
    # modified since uploaded?
    assert !invoice.modified_since_created?, "not modified since created"
    assert invoice.queue!
    assert !invoice.queue!
    assert !invoice.modified_since_created?, "state changes do not update timestamps"
    invoice.extra_info = "change something"
    invoice.state = :new
    assert invoice.save!
    assert invoice.modified_since_created?, "modified since created"
    # do not override email client1@email.com (is the same in XML)
    assert_nil invoice.client_email_override
  end

  test 'import facturae32 with discount on first line' do
    file = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_gob_es.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company6),"1234",'uploaded',User.current.name,nil,false)
    assert_equal 2, invoice.invoice_lines.size
    assert_equal 5, invoice.invoice_lines[0].discount_percent
    assert_equal 0, invoice.invoice_lines[1].discount_percent
    assert_equal 'Descuento', invoice.invoice_lines[0].discount_text
    assert_equal '132413842', invoice.invoice_lines[0].delivery_note_number
    assert_equal 'BBBH-38272', invoice.ponumber
    assert_equal 'BBBH-38272', invoice.invoice_lines.first.ponumber
    assert_equal Date.new(2010,3,9),  invoice.invoicing_period_start
    assert_equal Date.new(2010,3,10), invoice.invoicing_period_end
  end

  test 'when importing invoice with >1 discount on same line, add them' do
    file = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_gob_es2.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company6),"1234",'uploaded',User.current.name,nil,false)
    line = invoice.invoice_lines.first
    assert_equal 10, line.discount_percent
    assert_equal "Descuento. Descuento 2", line.discount_text
    assert_equal 2.50, line.discount_amount
  end

  test 'create invoice from facturae32 without saving original' do
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued3.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company1),"1234",'uploaded',User.current.name,nil,false)
    assert_nil invoice.original
  end

  test 'create invoice from facturae32 with line discounts and line charges' do
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued4.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company1),"1234",'uploaded',User.current.name,nil,false)
    assert_equal  0, invoice.total.dollars
    assert_equal 10, invoice.invoice_lines.first.charge
    assert_equal 10, invoice.invoice_lines.first.discount_percent
    assert_equal 'carrec linia1', invoice.invoice_lines.first.charge_reason
    assert_equal 'desc1', invoice.invoice_lines.first.discount_text
    assert_equal 'filereference', invoice.file_reference
    assert_equal 'filereference', invoice.invoice_lines.first.file_reference
    assert_nil invoice.invoice_lines.last.file_reference
  end

  test 'invoice with discount TotalAmount is same as TotalGrossAmountBeforeTaxes' do
    Invoice.all.each do |invoice|
      assert_equal (invoice.taxable_base.dollars + invoice.charge_amount.dollars), invoice.subtotal.dollars, "invoice #{invoice.id}"
    end
  end

  test 'imports dir3 data and stores it to db' do
    assert_nil Dir3Entity.find_by_code('P00000010')
    extcomp = ExternalCompany.find_by_taxcode 'ESB17915224'
    refute_match(/P00000010/, extcomp.organs_gestors)
    refute_match(/P00000010/, extcomp.unitats_tramitadores)
    refute_match(/P00000010/, extcomp.oficines_comptables)
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued4.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company1),"1234",'uploaded',User.current.name,nil,false)
    assert_equal('P00000010',invoice.organ_gestor)
    assert_equal('P00000010',invoice.unitat_tramitadora)
    assert_equal('P00000010',invoice.oficina_comptable)
    assert_equal('Oficina Comptable', invoice.oficina_comptable_name)
    dir3 = Dir3Entity.find_by_code('P00000010')
    assert_not_nil dir3
    assert_equal(dir3.name,'Oficina Comptable')
    assert_equal(dir3.address,'c. one two three, 34')
    assert_equal(dir3.postalcode,'08080')
    assert_equal(dir3.city,'Barcelona')
    assert_equal(dir3.province,'Barcelona')
    assert_equal(dir3.country,'es')
    extcomp = ExternalCompany.find_by_taxcode 'ESB17915224'
    assert_equal('P00000010', extcomp.oficines_comptables)
    assert_equal('P00000010', extcomp.organs_gestors)
    assert_equal('P00000011,P00000010', extcomp.unitats_tramitadores)
  end

  test 'invoice discounts are correctly calculated' do
    invoice = invoices(:i13)
    # line discounts
    line = invoice.invoice_lines.first
    assert_equal  10, line.discount_percent
    assert_equal 100, line.total_cost
    assert_equal  10, line.discount_amount
    assert_equal 100, line.taxable_base
    assert_equal  10, line.charge
    assert_equal 100, line.gross_amount
    assert_equal   1, line.taxes.size
    assert_equal  10, line.taxes.first.percent
    assert_equal  10, line.tax_amount(line.taxes.first)
    line = invoice.invoice_lines.last
    assert_equal   0, line.discount_percent
    assert_equal 100, line.total_cost
    assert_equal   0, line.discount_amount
    assert_equal 100, line.taxable_base
    assert_equal   1, line.taxes.size
    assert_equal  10, line.taxes.first.percent
    assert_equal  10, line.tax_amount(line.taxes.first)
    # invoice discounts
    assert_equal    10, invoice.discount_percent
    assert_equal    20, invoice.discount_amount.dollars
    assert_equal   180, invoice.taxable_base.dollars
    assert_equal   100, invoice.charge_amount.dollars
    assert_equal   280, invoice.subtotal.dollars
    assert_equal  18.0, invoice.tax_amount.dollars
    assert_equal 298.0, invoice.total.dollars
    assert_equal   200, invoice.gross_subtotal.dollars
  end

  # import invoice_facturae32_issued5.xml
  test 'create issued_invoice from facturae32 without PaymentMeans' do
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued5.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company1),"1234",'uploaded',User.current.name)
    assert_nil invoice.payment_method, "invoice payment should be nil and is #{invoice.payment_method}"
  end

  # import invoice_facturae32_issued6.xml
  test 'create issued_invoice from facturae32 when invoice taxcode includes country' do
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued6.xml'))
    invoice = Invoice.create_from_xml(file,User.find_by_login('jsmith'),"1234",'uploaded',User.current.name)
    assert_equal 'ES77310058C', invoice.company.taxcode # invoice taxcode: ES77310058C
  end

  # import invoice_facturae32_issued7.xml
  test 'create issued_invoice from facturae32 when company taxcode includes country' do
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued7.xml'))
    invoice = Invoice.create_from_xml(file,User.find_by_login('jsmith'),"1234",'uploaded',User.current.name)
    assert_equal 'ES77310058C', invoice.company.taxcode # invoice taxcode: 77310058C
  end

  test 'it rounds every line total before adding them' do
    assert_equal 119.22, invoices(:i14).total.dollars
  end

  # import invoice_facturae32_issued8.xml
  test 'it imports FactoringAssignmentData from facturae32' do
    file = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued8.xml'))
    invoice = Invoice.create_from_xml(file,User.find_by_login('jsmith'),"1234",'uploaded',User.current.name)
    assert_equal 'J',                        invoice.fa_person_type
    assert_equal 'R',                        invoice.fa_residence_type
    assert_equal 'ESA12345678',              invoice.fa_taxcode
    assert_equal 'A BANC, S.A.',             invoice.fa_name
    assert_equal 'Street, 1',                invoice.fa_address
    assert_equal '08080',                    invoice.fa_postcode
    assert_equal 'BARCELONA',                invoice.fa_town
    assert_equal 'BARCELONA',                invoice.fa_province
    assert_equal 'es',                       invoice.fa_country
    assert_equal '20000000000000000000',     invoice.fa_info
    assert_equal Date.new(2015,5,6),         invoice.fa_duedate
    assert_equal 372.08,                     invoice.fa_import
    assert_equal '04',                       invoice.fa_payment_method
    assert_equal 'ES1234567890123456789012', invoice.fa_iban
    assert_equal 'ABCABCAAXXX',              invoice.fa_bank_code
    assert_equal 'Clauses',                  invoice.fa_clauses
    assert invoice.debit?, "invoice payment is debit"
    assert_match(/2_\d+/, invoice.payment_method)
  end

  test 'overrides client email with client_email_override' do
    # Overrided:
    assert_equal "override@example.com", invoices(:i14).client_email_override
    assert_equal ["override@example.com"], invoices(:i14).recipient_emails
    # Not overrided
    assert_nil invoices(:i13).client_email_override
    assert_equal ["person1@example.com", "mail@client1.com"], invoices(:i13).recipient_emails
  end

  test 'it checks round_before_sum on company' do
    i = invoices(:i15)
    assert_equal false, i.company.round_before_sum
    assert_equal 1828.07, i.tax_amount.dollars
    assert_equal 1828.07, i.tax_amount(i.taxes.first).dollars
    i.company.round_before_sum = true
    assert_equal 1828.06, i.tax_amount.dollars
    assert_equal 1828.06, i.tax_amount(i.taxes.first).dollars
  end

  # import invoice_facturae32_issued11.xml
  test 'import invoice with discount amount and without discount percent' do
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued11.xml'))
    invoice = Invoice.create_from_xml(file,User.find_by_login('jsmith'),"1234",'uploaded',User.current.name)
    assert_equal 5.95, invoice.discount_percent.round(2)
    assert_equal 14.42, invoice.discount_amount.dollars
    il = invoice.invoice_lines.first
    assert_equal 101, il.total_cost
    assert_equal 10.0, il.discount_percent
    assert_equal 10.10, il.discount_amount
    assert_equal 242.40, invoice.gross_subtotal.dollars
    assert_equal BigDecimal.new('14.42').to_s, invoice.discount_amount.dollars.to_s
    assert_equal 85.49, invoice.taxable_base(invoice.taxes.select {|t| t.percent == 21 }.first).dollars
    assert_equal 142.49, invoice.taxable_base(invoice.taxes.select {|t| t.percent == 10 }.first).dollars
  end

  test 'when round_before_sum is checked and invoice has discounts, taxes are calculated correctly' do
    i = invoices(:i16)
    assert_equal false, i.company.round_before_sum
    assert_equal 90.00, i.subtotal.dollars
    assert_equal 9.00, i.tax_amount(i.taxes.first).dollars
    assert_equal 9.00, i.tax_amount.dollars
    assert_equal 99.00, i.total.dollars
    i.company.round_before_sum = true
    assert_equal true, i.company.round_before_sum
    assert_equal 90.00, i.subtotal.dollars
    assert_equal 9.00, i.tax_amount(i.taxes.first).dollars
    assert_equal 9.00, i.tax_amount.dollars
    assert_equal 99.00, i.total.dollars
  end

  # import invoice_facturae32_issued7.xml
  test 'create issued_invoice from facturae32 creates client_office when client data does not match' do
    assert_equal 1, clients(:clients_001).client_offices.count
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued7.xml'))
    invoice = Invoice.create_from_xml(file,User.find_by_login('jsmith'),"1234",'uploaded',User.current.name)
    assert_equal 2, clients(:clients_001).client_offices.count
    assert_equal clients(:clients_001).client_offices.last.id, invoice.client_office_id
  end

  # import invoice_facturae32_issued9.xml
  test 'create issued_invoice from facturae32 uses existing client_office when client data matches' do
    assert_equal 1, clients(:clients_001).client_offices.count
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued9.xml'))
    invoice = Invoice.create_from_xml(file,User.find_by_login('jsmith'),"1234",'uploaded',User.current.name)
    assert_equal 1, clients(:clients_001).client_offices.count
    assert_equal clients(:clients_001).client_offices.first.id, invoice.client_office_id
  end

  test 'import facturae32 with EquivalenceSurcharge taxes' do
    file = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_gob_es.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company6),"1234",'uploaded',User.current.name,nil,false)
    assert_equal(3, invoice.invoice_lines.last.taxes.size)
    re_taxes = invoice.invoice_lines.last.taxes.select {|tax| tax.name == 'RE'}
    assert_equal(1, re_taxes.size)
    re_tax = re_taxes.first
    assert_equal('S',re_tax.category)
    assert_equal(1.00,re_tax.percent)
  end

  test 'import UBL 2.0 with SBDH' do
    file = File.new(File.join(File.dirname(__FILE__),'../fixtures/documents/invoice_ubl_with_sbdh.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company6),"1234",'uploaded',User.current.name,nil,false)
    assert_equal '5503070490', invoice.client.taxcode
    assert_equal '908450385034', invoice.invoice_lines.first.article_code
    assert_equal 'line 1 note 30001', invoice.invoice_lines.first.notes
    if invoice.client.invoice_format == 'link_to_pdf_by_mail'
      assert invoice.valid?
      invoice.about_to_be_sent=true
      invoice.client.email=''
      assert !invoice.valid?
      assert_equal ["Invoice's client has no email defined"], invoice.errors.full_messages
    else
      assert invoice.valid?
    end
  end

  test 'invoice can repeat number+serie if year changes' do
    i = IssuedInvoice.new(invoices(:invoice1).attributes)
    i.invoice_lines = invoices(:invoice1).invoice_lines
    # invalid: same number+serie, same year
    assert !i.valid?
    assert(i.errors.messages.keys.include?(:number))
    # valid: same number+serie, same year
    i.date = i.date + 1.year
    assert i.valid?, i.errors.messages.to_s
    # valid: same number different serie, year ignored
    i.series_code = 16
    assert i.valid?, i.errors.messages.to_s
    i.date = invoices(:invoice1).date
    assert i.valid?, i.errors.messages.to_s
  end

  test 'import facturae32 with AmountsWithheld' do
    file = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_amounts_withheld.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company6),"1234",'uploaded',User.current.name,nil,false)
    assert_equal(50059.38, invoice.total.dollars)
    assert_equal(4678.45, invoice.amounts_withheld.dollars)
  end

  test 'change ponumber, file_reference and receiver_contract_reference on lines when changes on invoice' do
    invoice = IssuedInvoice.new(
      client_id: 1,
      date: '19-05-2016',
      number: '98789',
      terms: '0',
      due_date: '19-06-2016',
      import_in_cents: 8500,
      currency: 'EUR',
      payment_method: 1,
      project_id: 2,
      total_in_cents: 10030,
      ponumber: 'ponumber',
      file_reference: 'file_ref',
      receiver_contract_reference: 'rcr'
    )
    il = InvoiceLine.new(
      quantity: 1,
      description: 'desc',
      price: 10.0,
      unit: 1,
      ponumber: 'line_ponumber',
      file_reference: 'line_file_ref',
      receiver_contract_reference: 'line_rcr'
    )
    il.taxes << Tax.new(
      name: 'IVA',
      percent: 21.0,
      category: 'S'
    )
    invoice.invoice_lines << il
    assert invoice.save
    assert_equal('ponumber', invoice.ponumber)
    assert_equal('line_ponumber', invoice.invoice_lines.first.ponumber)
    assert_equal('file_ref', invoice.file_reference)
    assert_equal('line_file_ref', invoice.invoice_lines.first.file_reference)
    assert_equal('rcr', invoice.receiver_contract_reference)
    assert_equal('line_rcr', invoice.invoice_lines.first.receiver_contract_reference)
    invoice.payment_method = 2
    assert invoice.save
    assert_equal('ponumber', invoice.ponumber)
    assert_equal('line_ponumber', invoice.invoice_lines.first.ponumber)
    assert_equal('file_ref', invoice.file_reference)
    assert_equal('line_file_ref', invoice.invoice_lines.first.file_reference)
    assert_equal('rcr', invoice.receiver_contract_reference)
    assert_equal('line_rcr', invoice.invoice_lines.first.receiver_contract_reference)
    invoice.ponumber = 'new_ponumber'
    invoice.file_reference = 'new_file_ref'
    invoice.receiver_contract_reference = 'new_rcr'
    assert invoice.save
    assert_equal('new_ponumber', invoice.ponumber)
    assert_equal('new_ponumber', invoice.invoice_lines.first.ponumber)
    assert_equal('new_file_ref', invoice.file_reference)
    assert_equal('new_file_ref', invoice.invoice_lines.first.file_reference)
    assert_equal('new_rcr', invoice.receiver_contract_reference)
    assert_equal('new_rcr', invoice.invoice_lines.first.receiver_contract_reference)
  end

  test 'import invoice and create client linked to an external company' do
    ext_comp = ExternalCompany.find_by_taxcode 'ESB17915224'
    assert_not_nil ext_comp
    assert_nil Client.find_by_taxcode 'ESB17915224'
    file    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued10.xml'))
    invoice = Invoice.create_from_xml(file,User.find_by_login('jsmith'),"1234",'uploaded',User.current.name)
    assert_equal 'ESB17915224', invoice.client.taxcode
    client = Client.find_by_taxcode 'ESB17915224'
    assert_not_nil client
    assert_not_nil client.company
    assert_equal client.company, ext_comp
  end

  test 'import invoice with existing client linked to an external company' do
    ext_comp = ExternalCompany.find_by_taxcode 'ESB17915224'
    assert_not_nil ext_comp
    assert_nil Client.find_by_taxcode 'ESB17915224'
    client = Client.create!(project_id: 2, company: ext_comp)
    assert_equal ext_comp.id, client.company_id
    file = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued10.xml'))
    invoice = Invoice.create_from_xml(file,User.find_by_login('jsmith'),"1234",'uploaded',User.current.name)
    assert_equal invoice.client, client
    assert_equal ext_comp.id, invoice.client.company_id
  end

  test 'import invoice does not create client_office when values are blank' do
    invoice = invoices(:invoices_001)
    client = invoice.client
    assert_equal 'Client1', client.name
    assert_equal 1, client.client_offices.size

    invoice.client, invoice.client_office = Haltr::Utils.client_from_hash(
      :taxcode        => "A13585625",
      :name           => nil,
      :address        => nil,
      :province       => nil,
      :country        => nil,
      :website        => nil,
      :email          => nil,
      :postalcode     => nil,
      :city           => nil,
      :currency       => nil,
      :project        => invoice.project,
      :invoice_format => nil,
      :language       => nil,
    )
    assert_equal 1, client.client_offices.size
  end

  # import invoice_facturae32_issued8_iban2.xml
  test 'import invoice with iban != client.iban stores iban on invoice' do
    file     = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued8.xml'))
    file2    = File.new(File.join(File.dirname(__FILE__),'..','fixtures','documents','invoice_facturae32_issued8_iban2.xml'))
    assert_nil Client.find_by_taxcode 'ESP1700000A'
    invoice  = Invoice.create_from_xml(file,User.find_by_login('jsmith'),"1234",'uploaded',User.current.name)
    assert_not_nil Client.find_by_taxcode 'ESP1700000A'
    assert_equal 'ES8023100001180000012345', invoice.client.iban
    assert_equal 'biiiiiiiiic', invoice.client.bic
    invoice2 = Invoice.create_from_xml(file2,User.find_by_login('jsmith'),"1234",'uploaded',User.current.name)
    assert_equal 'ES8023100001180000012345', invoice.client.iban
    assert_equal 'biiiiiiiiic', invoice.client.bic
    assert_equal 'ES8023100001180000012345', invoice2.client.iban
    assert_equal 'ES0000000000000000000000', invoice2.client_iban
    assert_equal 'biiiiiiiic2', invoice2.client_bic
  end

  # ExternalCompany taxcode is ESB17915224
  test 'does not link to external_company if taxcode does not match' do
    invoice = invoices(:invoices_001)
    invoice.client = nil
    invoice.client, invoice.client_office = Haltr::Utils.client_from_hash(
      name: 'test',
      language: 'en',
      country: 'fr',
      taxcode: "FR60528551658",
      project: invoice.project
    )
    assert_nil invoice.client.company_id
  end

  test 'does not link to external_company with short taxcodes' do
    invoice = invoices(:invoices_001)
    invoice.client = nil
    invoice.client, invoice.client_office = Haltr::Utils.client_from_hash(
      name: 'test',
      language: 'en',
      country: 'fr',
      taxcode: "FR60528551658",
      project: invoice.project
    )
    assert_nil invoice.client.company_id
  end

  test 'links to external_company if taxcode matches but has no country code' do
    invoice = invoices(:invoices_001)
    invoice.client = nil
    invoice.client, invoice.client_office = Haltr::Utils.client_from_hash(
      taxcode: "B17915224",
      project: invoice.project
    )
    assert_not_nil invoice.client.company_id
    assert_equal 'ESB17915224', invoice.client.taxcode
  end

  test 'links to external_company if taxcode matches' do
    invoice = invoices(:invoices_001)
    invoice.client = nil
    invoice.client, invoice.client_office = Haltr::Utils.client_from_hash(
      taxcode: "ESB17915224",
      project: invoice.project
    )
    assert_not_nil invoice.client.company_id
    assert_equal 'ESB17915224', invoice.client.taxcode
  end

  test 'import UBL 2.1 with attachments' do
    file = File.new(File.join(File.dirname(__FILE__),'../fixtures/documents/invoice_ubl_with_attachments.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company6),"1234",'uploaded',User.current.name,nil,false)
    assert_equal 'SE841215495001', invoice.client.taxcode
    assert_equal 2, invoice.attachments.size
  end

  test 'import facturae with invalid IBAN in PaymentDetails raises error with I18n translation' do
    I18n.locale = :es
    xml = File.new(File.join(File.dirname(__FILE__),'../fixtures/documents/invoice_facturae32_issued8.xml')).read
    xml.gsub!('ES8023100001180000012345','ESXXXXXXXXXXXXXXX000012345')
    err = assert_raises RuntimeError do
      Invoice.create_from_xml(xml,companies(:company1),"1234",'uploaded',User.current.name,nil,false)
    end
    assert_equal "La validación ha fallado: El IBAN no es válido", err.message
    I18n.locale = :en
  end

  test 'import more fields from UBL 2.0' do
    file = File.new(File.join(File.dirname(__FILE__),'../fixtures/documents/invoice_ubl_with_sbdh.xml'))
    invoice = Invoice.create_from_xml(file,companies(:company6),"1234",'uploaded',User.current.name,nil,false)
    xml = Nokogiri::XML(Haltr::Xml.generate(invoice, 'peppolubl21', false, false, true))
    xml.remove_namespaces!
    assert_equal 'Invoice notes', invoice.extra_info # ho importem
    assert_equal 'Invoice notes', xml.at('//Invoice/Note').text # ho posem a l'xml
    assert_equal 'ISK', invoice.currency
    assert_equal 'ISK', xml.at('//Invoice/DocumentCurrencyCode').text
    assert_equal '20068', invoice.ponumber
    assert_equal '20068', xml.at('//Invoice/OrderReference/ID').text
    assert_equal '20068', invoice.invoice_lines.first.ponumber #TODO: a ubl ho hem de posar a linia tmb?
    assert_equal 'Contract01', invoice.contract_number
    assert_equal 'Contract01', xml.at('//Invoice/ContractDocumentReference/ID').text
    #assert_equal 1, invoice.client.people.size
    #person = invoice.client.people.first
    #assert_equal 'Customer', person.name
    #assert_equal '123-4560', person.phone_office
    ##assert_equal '123-4678', person.phone_fax
    #assert_equal 'test@customer.com', person.email
    #assert_equal 'Customer', xml.at('//Invoice/AccountingCustomerParty/Party/Contact/Name')
    #assert_equal '123-4560', xml.at('//Invoice/AccountingCustomerParty/Party/Contact/Telephone')
    ##assert_equal '123-4678', xml.at('//Invoice/AccountingCustomerParty/Party/Contact/Telefax')
    #assert_equal 'test@customer.com', xml.at('//Invoice/AccountingCustomerParty/Party/Contact/ElectronicMail')

    assert_equal 'Ísvatn 19L ID GREN DSK', invoice.invoice_lines[0].description
    assert_equal 'Ísvatn 19L ID GREN DSK', xml.xpath('//Invoice/InvoiceLine/Item/Name')[0].text
    assert_equal InvoiceLine::OTHER, invoice.invoice_lines[0].unit
    assert_equal InvoiceLine::UNITS, invoice.invoice_lines[1].unit
    assert_equal InvoiceLine::UNITS, invoice.invoice_lines[2].unit
    assert_equal 'line 1 note 30001', invoice.invoice_lines[0].notes
    assert_equal 'line 1 note 30001', xml.xpath('//Invoice/InvoiceLine/Note')[0].text
    assert_equal 'line 2 note 30006', invoice.invoice_lines[1].notes
    assert_equal 'line 3 note 30005', invoice.invoice_lines[2].notes
    # delivery
    assert_equal Date.parse('2017-05-19'), invoice.delivery_date
    assert_equal '2017-05-19', xml.at('//Invoice/Delivery/ActualDeliveryDate').text
    assert_equal 'GLN', invoice.delivery_location_type
    assert_equal 'GLN', xml.at('//Invoice/Delivery/DeliveryLocation/ID/@schemeID').text
    assert_equal '1234567890123', invoice.delivery_location_id
    assert_equal '1234567890123', xml.at('//Invoice/Delivery/DeliveryLocation/ID').text
    assert_equal 'Melió 113', invoice.delivery_address
    assert_equal 'Melió 113', xml.at('//Invoice/Delivery/DeliveryLocation/Address/StreetName').text
    assert_equal 'Vilafranca del Penedès', invoice.delivery_city
    assert_equal 'Vilafranca del Penedès', xml.at('//Invoice/Delivery/DeliveryLocation/Address/CityName').text
    assert_equal '08720', invoice.delivery_postalcode
    assert_equal '08720', xml.at('//Invoice/Delivery/DeliveryLocation/Address/PostalZone').text
    assert_equal 'Barcelona', invoice.delivery_province
    assert_equal 'Barcelona', xml.at('//Invoice/Delivery/DeliveryLocation/Address/CountrySubentity').text
    assert_equal 'ES', invoice.delivery_country
    assert_equal 'ES', xml.at('//Invoice/Delivery/DeliveryLocation/Address/Country/IdentificationCode').text
  end

end
