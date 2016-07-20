module BrNfe
	class Base < BrNfe::ActiveModelBase
		
		include BrNfe::Helper::HaveEmitente

		attr_accessor :certificate_pkcs12_password
		attr_accessor :certificate_pkcs12_path
		attr_accessor :certificate_pkcs12_value
		attr_accessor :env

		attr_accessor :client_wsdl_ssl_verify_mode
		attr_accessor :client_wsdl_ssl_cert_file
		attr_accessor :client_wsdl_ssl_cert_key_file
		attr_accessor :client_wsdl_ssl_cert_key_password

		validate :validar_emitente
		validates :certificate, :certificate_key, presence: true, if: :certificado_obrigatorio?

		# Método que deve ser sobrescrito para as ações que necessitam do certificate_pkcs12 para assinatura
		def certificado_obrigatorio?
			false
		end

		def env
			@env ||= :production
		end

		def original_response
			@original_response
		end

		def response
			@response
		end
		
		# Namespace da requisição SOAP
		#
		def env_namespace
			:soapenv
		end

		# Deve conter o LINK do webservice a ser chamado
		#
		def wsdl
			raise "Não implementado."
		end

		# Método que contem qual a operação que deverá ser chamada
		# do WS SOAP.
		#
		def method_wsdl
			raise "Não implementado."
		end

		# O xml_builder é o que contém o conteúdo de cada tipo de requisição
		# e deve ser sobrescrito em cada classe implementada. Por exemplo:
		# recepcao_lote_rps, consulta_lote_rps, cancelamento_nfs, etc..
		#
		def xml_builder
			raise "Não implementado."
		end

		# Esse método serve para ser utilizado no Base de cada orgão emissor
		# onde em alguns casos é necessário colocar o xml em um CDATA
		# É esse método que é passado dentro do Body da equisição SOAP
		#
		def content_xml
			xml_builder
		end

		# O Namespace Indentifier é utilizado para adicionar o
		# namespace na tag principal da requisição. Normalmente deve seguir 
		# o namespace utilizado para identificar o namespace da mensagem.
		#
		# Exemplo: se o método message_namespaces for {xmlns:ns1="http...."} então
		# o namespace_identifier deveria ser :ns1.
		# E com isso irá adicionar o namespace na tag principal da requsição. 
		# Exemplo com a requisição EnviarLoteRps:
		# COM namespace_identifier => ns1:EnviarLoteRpsEnvio
		# SEM namespace_identifier => EnviarLoteRpsEnvio
		#
		# <b>Tipo de retorno: </b> _Hash_ OR _Nil_
		#
		def namespace_identifier
		end

		def message_namespaces
			{}
		end

		def soap_namespaces
			{
				'xmlns:soapenv' => 'http://schemas.xmlsoap.org/soap/envelope/',
				'xmlns:ins0'    => 'http://www.w3.org/2000/09/xmldsig#',
				'xmlns:xsd'     => 'http://www.w3.org/2001/XMLSchema',
				'xmlns:xsi'     => 'http://www.w3.org/2001/XMLSchema-instance'
			}
		end

		def wsdl_encoding
			"UTF-8"
		end

		# Tag XML que vai na requisição SOAP
		#
		# <b>Tipo de retorno: </b> _String_
		#
		def tag_xml
			"<?xml version=\"1.0\" encoding=\"#{wsdl_encoding}\"?>"
		end

		# Versão do XML utilizado 
		# Cada Cidade pode utilizar uma versão diferente do XML
		#
		# <b>Tipo de retorno: </b> _Symbol_
		#
		def xml_version
			:v1
		end

		def client_wsdl
			@client_wsdl ||= Savon.client({
				wsdl:                  wsdl,
				log:                   BrNfe.client_wsdl_log,
				pretty_print_xml:      BrNfe.client_wsdl_pretty_print_xml,

				ssl_verify_mode:       client_wsdl_ssl_verify_mode,
				ssl_cert_file:         client_wsdl_ssl_cert_file,
				ssl_cert_key_file:     client_wsdl_ssl_cert_key_file,
				ssl_cert_key_password: client_wsdl_ssl_cert_key_password
			})
		end

		def client_wsdl_ssl_verify_mode
			@client_wsdl_ssl_verify_mode ||= BrNfe.client_wsdl_ssl_verify_mode
		end
		def client_wsdl_ssl_cert_file
			@client_wsdl_ssl_cert_file ||= BrNfe.client_wsdl_ssl_cert_file
		end
		def client_wsdl_ssl_cert_key_file
			@client_wsdl_ssl_cert_key_file ||= BrNfe.client_wsdl_ssl_cert_key_file
		end
		def client_wsdl_ssl_cert_key_password
			@client_wsdl_ssl_cert_key_password ||= BrNfe.client_wsdl_ssl_cert_key_password
		end

		# Caso não tenha o certificate_pkcs12 salvo em arquivo, pode setar a string do certificate_pkcs12 direto pelo atributo certificate_pkcs12_value
		# Caso tenha o certificate_pkcs12 em arquivo, basta setar o atributo certificate_pkcs12_path e deixar o atributo certificate_pkcs12_value em branco
		def certificate_pkcs12_value
			@certificate_pkcs12_value ||= File.read(certificate_pkcs12_path)
		end

		def certificate_pkcs12
			@certificate_pkcs12 ||= OpenSSL::PKCS12.new(certificate_pkcs12_value, certificate_pkcs12_password)
		rescue
		end

		def certificate_pkcs12=(value)
			@certificate_pkcs12 = value
		end

		def certificate=(value)
			@certificate = value
		end

		def certificate
			@certificate ||= certificate_pkcs12.try :certificate
		end

		def certificate_key
			@certificate_key ||= certificate_pkcs12.try :key
		end

		def certificate_key=(value)
			@certificate_key = value
		end		

		# Renderiza o xml a partir do nome de um arquivo 
		# Irá procurar o arquivo a partir dos seguintes diretórios>
		# 1° - A partir do parâmetro  :dir_path
		# 2° - A partir do método   xml_current_dir_path
		# 3° - A partir do método  xml_default_dir_path
		# 
		# Se não encontrar o arquivo em nenhum dos diretórios irá execurar
		# uma excessão de RuntimeError
		#
		# Utilização
		# `render_xml('file_name', {dir_path: '/my/custom/dir', context: Object}`
		# 
		# <b>Tipo de retorno: <b> _String_ (XML)
		#
		def render_xml file_name, opts={}
			opts ||= {}
			default_options = opts.extract!(:dir_path, :context)
			default_options[:context] ||= self
			
			# Inicializa a variavel xml com nil para comparar se oa rquivo foi de fato encontrado.
			xml = nil
			get_xml_dirs(default_options[:dir_path]).each do |dir|
				if xml = find_xml(file_name, dir, default_options[:context], opts)
					break # Stop loop
				end
			end

			# Lança uma excessão se não for encontrado o xml
			# Deve verificar se é nil pois o arquivo xml pode estar vazio
			if xml.nil?
				raise "Arquivo #{file_name}.xml.slim não encontrado nos diretórios #{get_xml_dirs(default_options[:dir_path])}" 
			end
			xml
		end

		def find_xml(file_name, dir, context=nil, options={})
			if File.exists?("#{dir}/#{file_name}.xml.slim")
				Slim::Template.new("#{dir}/#{file_name}.xml.slim").render(context, options).html_safe 
			end
		end

		def get_xml_dirs(custom_dir_path=nil)
			[custom_dir_path, xml_current_dir_path, xml_default_dir_path].flatten.select(&:present?)
		end

		# Diretório personalizado para cada classe
		# Podendo ser sobrescrito em cada herança
		#
		def xml_current_dir_path
			[]
		end
		 
		# Diretório padrão dos arquivos XML
		#
		def xml_default_dir_path
			"#{BrNfe.root}/lib/br_nfe/xml"
		end

	private

		def tag_cpf_cnpj(xml, cpf_cnpj)
			cpf_cnpj = BrNfe::Helper::CpfCnpj.new(cpf_cnpj)
			if cpf_cnpj.cnpj?
				xml.Cnpj cpf_cnpj.sem_formatacao
			elsif cpf_cnpj.cpf?				
				xml.Cpf  cpf_cnpj.sem_formatacao
			end
		end


		def assinatura_xml(data_xml, uri='')
			data_xml = format_data_xml_for_signature(data_xml)
			ass = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
				xml.Signature(xmlns: 'http://www.w3.org/2000/09/xmldsig#') do |signature|
					
					info = canonicalize(signed_info(data_xml, uri).doc.root())
					signature.__send__ :insert, Nokogiri::XML::DocumentFragment.parse( info.to_s ) 
					
					signature.SignatureValue xml_signature_value(info)
					
					signature.KeyInfo {
						signature.X509Data {
							signature.X509Certificate certificate.to_s.gsub(/\-\-\-\-\-[A-Z]+ CERTIFICATE\-\-\-\-\-/, "").gsub(/\n/,"")
						}
					}
				end
			end.doc.root
			canonicalize ass
		end

		def canonicalization_method_algorithm
			'http://www.w3.org/2001/10/xml-exc-c14n#'
		end

		def signed_info(data_xml, uri='')
			Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
				xml.SignedInfo(xmlns: "http://www.w3.org/2000/09/xmldsig#") do |info|
					info.CanonicalizationMethod(Algorithm: canonicalization_method_algorithm)
					info.SignatureMethod(Algorithm: 'http://www.w3.org/2000/09/xmldsig#rsa-sha1')
					info.Reference('URI' => uri){ 
						info.Transforms{
							info.Transform(:Algorithm => 'http://www.w3.org/2000/09/xmldsig#enveloped-signature')
							info.Transform(:Algorithm => 'http://www.w3.org/TR/2001/REC-xml-c14n-20010315')
						}
						info.DigestMethod(:Algorithm => 'http://www.w3.org/2000/09/xmldsig#sha1')
						info.DigestValue xml_digest_value(data_xml)
					}
				end
			end
		end

		def xml_signature_value(xml)
			sign_canon = canonicalize(xml)
			signature_hash  = certificate_key.sign(OpenSSL::Digest::SHA1.new, sign_canon)
			remove_quebras Base64.encode64( signature_hash )
		end

		def xml_digest_value(xml)
			xml_canon = canonicalize(xml)
			remove_quebras Base64.encode64(OpenSSL::Digest::SHA1.digest(xml_canon))
		end


		def canonicalize(xml)
			xml = Nokogiri::XML(xml.to_s, &:noblanks)
			xml.canonicalize(Nokogiri::XML::XML_C14N_EXCLUSIVE_1_0)
		end

		def remove_quebras(str)
			str.gsub(/\n/,'').gsub(/\t/,'').strip
		end

		def format_data_xml_for_signature(data_xml)
			data_xml
		end

		def validar_emitente
			if emitente.invalid?
				emitente.errors.full_messages.map{|msg| errors.add(:base, "Emitente: #{msg}") }
			end
		end

	end
end