class Order < ActiveRecord::Base
  unloadable

  belongs_to :project
  belongs_to :client
  has_many :comments, :as => :commented, :dependent => :delete_all, :order => "created_on"
  has_many :events, :order => :created_at
  after_create :create_event

  REGEXPS = {
    # camps que es desaran a la bbdd
    num_pedido:      /ORD=([^:]*)::/,
    fecha_pedido:    /ORD=[^:]*::([^+]*)\+\+.'/,
    lugar_entrega:   /CLO=:[^+]*\+([^+]*)\+/,
    fecha_entrega:   /DIN=([^']*)'/,
    fecha_documento: /FIL=[0-9]+\+[0-9]\+([^']*)'/,
    # camps que no es desen a la bbdd
    datos_proveedor:   /SDT=([^:]*):([^+]*)\+([^+]*)\+([^:]*):([^:]*):([^:]*):([^:]*):([^']*)'/,
    datos_cliente:     /CDT=([^:]*):([^+]*)\+([^+]*)\+([^:]*):([^:]*):([^:]*):([^:]*):([^']*)'/,
    direccion_entrega: /CLO=:([^+]*)\+([^+]*)\+([^:]*):([^:]*):([^:]*):([^:]*):([^']*)'/,
    lineas_pedido:     /OLD=([^+]*)\+:([^+]*)\+\+:([^+]*)\+([^+]*)\+([^+]*)\+([^+]*)\+\+\+([^']*)'/,
  }

  REGEXPS2 = {
    # camps que es desaran a la bbdd
    num_pedido:      /BGM\+[^+]+\+([0-9]+)\+/,
    fecha_pedido:    /DTM\+137:([0-9]+):/,
    lugar_entrega:   /NAD\+DP\+[^+]*\+[^+]*\+([^+]*\+[^+]*\+[^+]*\+[^+]*\+[^+]*)'/,
    fecha_entrega:   /DTM\+2:([0-9]+):/,
    fecha_documento: /UNB\+[^+]*\+[^+]*\+[^+]*\+([^+]*):/,
    # camps que no es desen a la bbdd
    datos_proveedor:   /NAD\+SU\+([^:+]*):/,
    datos_cliente:     /NAD\+BY\+([^:+]*):/,
    direccion_entrega: /NAD\+DP\+([^+:]*)[^+]*\+[^+]*\+([^+]*)\+([^+]*)\+([^+]*)\+([^+]*)\+()([^+]*)'/,
    lineas_pedido:     /LIN\+[^+]*\+[^+]*\+([^+]*)'/,
  }

  REGEXPS_KEYS = {
    datos_proveedor:   %w(codigo_po nombre_po sociedad direccion1 direccion2 direccion3 direccion4 cp),
    datos_cliente:     %w(codigo_po nombre_po sociedad direccion1 direccion2 direccion3 direccion4 cp),
    direccion_entrega: %w(codigo_cliente lugar_entrega direccion1 direccion2 direccion3 direccion4 cp),
    lineas_pedido:     %w(linea_pedido codigo_articulo_proveedor codigo_articulo_cliente unidades_consumo cantidad precio descripcion)
  }

  XPATHS_ORDER = {
    num_pedido:      "/xmlns:Order/cbc:ID",
    fecha_pedido:    "/xmlns:Order/cbc:IssueDate",
    lugar_entrega:   "/xmlns:Order/cac:Delivery/cac:DeliveryLocation/cbc:ID",
    fecha_entrega:   "/xmlns:Order/cac:Delivery/cac:RequestedDeliveryPeriod/cbc:EndDate",
    fecha_documento: "/xmlns:Order/cbc:IssueDate",
    buyer:           "/xmlns:Order/cac:BuyerCustomerParty/cac:Party",
    seller:          "/xmlns:Order/cac:SellerSupplierParty/cac:Party",
    # camps que no es desen a la bbdd
    #datos_proveedor:   "",
    #datos_cliente:     "",
    #direccion_entrega: "",
    #lineas_pedido:     "",
  }

  # relatius a seller o buyer
  XPATHS_PARTY = {
    taxcode:    "/cac:PartyTaxScheme/cbc:CompanyID",
    name:       "/cac:PartyName/cbc:Name",
    endpointid: "/cbc:EndpointID", # peppol
    address:    "/cac:PostalAddress/cbc:StreetName",
    city:       "/cac:PostalAddress/cbc:CityName",
    postalcode: "/cac:PostalAddress/cbc:PostalZone",
    province:   "/cac:PostalAddress/cbc:CountrySubentity",
    country:    "/cac:PostalAddress/cac:Country/cbc:IdentificationCode",
  }

  def self.regexps(edi)
    !!(edi =~ REGEXPS[:num_pedido]) ? REGEXPS : REGEXPS2
  end

  def regexps
    Order.regexps(original)
  end

  def self.create_from_edi(file, project)
    edi = file.read
    order = ReceivedOrder.new(
      project: project,
      original: edi,
      filename: file.original_filename
    )
    rgxps = order.regexps
    rgxps.keys.each do |key|
      next unless order.respond_to? "#{key}="
      if edi =~ rgxps[key]
        order.send("#{key}=", rgxps[key].match(edi)[1])
      else
        order.send("#{key}=", "?")
      end
    end
    order.save!
    order
  end

  def self.create_from_xml(file, project)
    file_name = nil
    if file.respond_to? :filename             # Mail::Part
      file_name = file.filename
    elsif file.respond_to? :original_filename # UploadedFile
      file_name = file.original_filename
    elsif file.respond_to? :path              # File (tests)
      file_name = File.basename(file.path)
    else
      file_name = "order.xml"
    end

    xml = file.read
    doc = Nokogiri::XML(xml)
    if doc.child and doc.child.name == "StandardBusinessDocument"
      doc = Haltr::Utils.extract_from_sbdh(doc)
    end
    seller_taxcode  = Haltr::Utils.get_xpath(doc, "#{XPATHS_ORDER[:seller]}#{XPATHS_PARTY[:taxcode]}")
    seller_endpoint = Haltr::Utils.get_xpath(doc, "#{XPATHS_ORDER[:seller]}#{XPATHS_PARTY[:endpointid]}")
    buyer_taxcode   = Haltr::Utils.get_xpath(doc, "#{XPATHS_ORDER[:buyer]}#{XPATHS_PARTY[:taxcode]}")
    buyer_endpoint  = Haltr::Utils.get_xpath(doc, "#{XPATHS_ORDER[:buyer]}#{XPATHS_PARTY[:endpointid]}")

    if project.company.taxcode == seller_taxcode or project.company.endpointid == seller_endpoint
      client_role = :buyer
      client_taxcode = buyer_taxcode
    elsif project.company.taxcode == buyer_taxcode or project.company.endpointid == buyer_endpoint
      client_role = :seller
      client_taxcode = seller_taxcode
    else
      peppolid = ", #{project.company.schemeid} #{project.company.endpointid}"
      raise I18n.t :taxcodes_does_not_belong_to_self,
        :tcs => "#{buyer_taxcode}/#{buyer_endpoint} - #{seller_taxcode}/#{seller_endpoint}",
        :tc  => "#{project.company.taxcode}#{peppolid if peppolid.size > 3}"
    end

    client = project.clients.find_or_initialize_by_taxcode(client_taxcode)
    if client.new_record?
      client.project = project
      XPATHS_PARTY.each do |key, xpath|
        value = Haltr::Utils.get_xpath(doc, "#{XPATHS_ORDER[client_role]}#{xpath}")
        client.send("#{key}=",value)
      end
      client.language = User.current.language
      client.country.downcase! rescue nil
      if !Valvat::Checksum.validate(client.taxcode)
        client.company_identifier = client.taxcode
        client.taxcode = ""
      end
      unless client.save
        raise "CLIENT: #{client.errors.full_messages.join('. ')}"
      end
    else
      #TODO: seus?
    end
    order = (client_role == :buyer) ? ReceivedOrder.new : IssuedOrder.new
    order.client = client
    order.project  = project
    order.original = xml
    order.filename = file.original_filename

    XPATHS_ORDER.each do |key, xpath|
      next unless order.respond_to?("#{key}=")
      value = Haltr::Utils.get_xpath(doc, xpath)
      order.send("#{key}=",value)
    end
    order.filename = file_name
    unless order.save
      raise "ORDER: #{order.errors.full_messages.join('. ')}"
    end
    order
  end

  def xml?
    original =~ /^<\?xml/
  end

  def edi?
    !xml?
  end

  def datos_proveedor
    if edi?
      captures = regexps[:datos_proveedor].match(original).captures
      Hash[REGEXPS_KEYS[:datos_proveedor].zip(captures)]
    else
    end
  end

  def datos_cliente
    if edi?
      captures = regexps[:datos_cliente].match(original).captures
      Hash[REGEXPS_KEYS[:datos_cliente].zip(captures)]
    else
    end
  end

  def direccion_entrega
    if edi?
      captures = regexps[:direccion_entrega].match(original).captures
      Hash[REGEXPS_KEYS[:direccion_entrega].zip(captures)]
    else
    end
  end

  def lineas_pedido
    if edi?
      original.scan(regexps[:lineas_pedido]).collect do |captures|
        Hash[REGEXPS_KEYS[:lineas_pedido].zip(captures)]
      end
    else
    end
  end

  def next
    Order.first(conditions: ["project_id = ? and id > ? and type = ?", project.id, id, type])
  end

  def previous
    Order.first(conditions: ["project_id = ? and id < ? and type = ?", project.id, id, type])
  end

  protected

  def create_event
    if self.original
      event = EventWithFile.new(:name=>'uploaded',:order_id=>self.id,
                                :user=>User.current,:file=>self.original,
                                :filename=>self.filename,:project=>self.project)
    else
      event = Event.new(:name=>'uploaded',:order_id=>self.id,
                        :user=>User.current,:project=>self.project)
    end
    #event.audits = self.last_audits_without_event
    event.save!
  end

end
