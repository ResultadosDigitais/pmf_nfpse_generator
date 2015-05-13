#coding: utf-8

require 'csv'
require 'builder'
require 'httparty'
require 'active_model'

class PmfNfpseGenerator
  include ActiveModel::Validations

  attr_accessor :config
  attr_accessor :cities
  attr_accessor :cpf_cnpj, :name, :address, :zipcode, :state, :city, :email, :cfps, :billing_date, :items, :extra_info

  validates_presence_of :cpf_cnpj, :name, :address, :zipcode, :state, :city, :email, :billing_date, :items

  def initialize(attrs = {})
    # {:cpf_cnpj=>"13.372.575/0001-87", :name=>"SOCIALBASE SOLUCOES EM TECNOLOGIA LTDA", :address=>"Rod SC 401", :city=>"Florianópolis", :zipcode=>"88030-000", :state=>"SC", :email=>"pedro.bachiega-22@resultadosdigitais.com.br", :cfps=>nil, :items=>[{:price=>919, :cnae_id=>"9178", :cnae_code=>"6203100", :cnae_desc=>"SERVIÇO DE LICENCIAMENTO DE PROGRAMA DE MARKETING DIGITAL - RD STATION", :cnae_aliquota=>0.02, :cst=>"0"}, {:price=>750, :cnae_id=>"9177", :cnae_code=>"6204000", :cnae_desc=>"CONSULTORIA EM TECNOLOGIA DA INFORMAÇÃO E MARKETING DIGITAL - RD STATION", :cnae_aliquota=>0.02, :cst=>"0"}], :extra_info=>nil}
    self.cpf_cnpj = attrs[:cpf_cnpj]
    self.name = attrs[:name]
    self.address = attrs[:address]
    self.zipcode = attrs[:zipcode]
    self.state = attrs[:state]
    self.city = attrs[:city]
    self.email = attrs[:email]
    self.cfps = attrs[:cfps]

    self.billing_date = attrs[:billing_date]

    self.items = attrs[:items]

    self.extra_info = attrs[:extra_info]
  end

  def configure
    self.config ||= Configuration.new
    yield(config)
  end

  class Configuration
    attr_accessor :TipoSistema, :Emissor_Identificacao, :Emissor_AEDF, :Emissor_TipoAedf, :Emissor_Cidade, :Emissor_Estado, :Impostos
  end

  # {"city"=>"Curitiba", "state"=>"PR", "city_ibge_code"=>"4106902", "source"=>"csv"}
  def to_xml!
    return nil unless self.valid?

    city_info = get_city_info(zipcode.gsub(".",""), state, city)
    date = DateTime.strptime(billing_date, '%d/%m/%Y')
    now = DateTime.strptime("#{DateTime.now.day}/#{DateTime.now.month}/#{DateTime.now.year}", '%d/%m/%Y')
    raise "A Data de emissão, não pode ser uma data futura." if date != now && date > now
    date = date.strftime('%Y-%m-%d')

    xml = Builder::XmlMarkup.new( :indent => 2 )
    xml.instruct! :xml, :encoding => "UTF-8"
    xml.InfRequisicao("xmlns" => "http://nfe.pmf.sc.gov.br/nfse/versao?tipo=xsd-2_0", "xmlns:dsig" => "http://www.w3.org/2000/09/xmldsig") do |root|
      root.Versao "2.0"
      root.TipoSistema "#{config.TipoSistema}"
      root.Identificacao "#{config.Emissor_Identificacao}"
      root.AEDF do |aedf|
        aedf.AEDF "#{config.Emissor_AEDF}"
        aedf.TipoAedf "#{config.Emissor_TipoAedf}"
      end
      root.DataEmissao "#{date}Z"

      # root.CFPS "#{cfps}"
      if city_info["city"] == "#{config.Emissor_Cidade}"
        root.CFPS "9201"
      elsif city_info["state"] == "#{config.Emissor_Estado}"
        root.CFPS "9202"
      else
        root.CFPS "9203"
      end

      root.DadosServico do |servicos|

        total = 0
        issqn = 0

        items.each do |_item|
          # {:price=>919, :cnae_id=>"9178", :cnae_code=>"6203100", :cnae_desc=>"SERVIÇO DE LICENCIAMENTO DE PROGRAMA DE MARKETING DIGITAL - RD STATION", :cnae_aliquota=>0.02, :cst=>"0"}
          price = _item[:price].to_f
          aliquota = _item[:cnae_aliquota]
          issqn += (price * aliquota).round(2)
          total += price
          servicos.ItemServico do |item|
            item.IdCNAE _item[:cnae_id]
            item.CodigoAtividade _item[:cnae_code]
            item.DescricaoServico _item[:cnae_desc]
            item.CST _item[:cst]
            item.Aliquota aliquota
            item.ValorUnitario price
            item.Quantidade "1"
            item.ValorTotal price
          end
        end

        servicos.BaseCalculo total.round(2)
        servicos.ValorISSQN issqn.round(2)
        servicos.ValorTotalServicos total.round(2)

        _extra_info = extra_info
        # CSRF (4,65%)
        if total > 5000
          csrf = (total*0.0465).round(2).to_s.gsub(".", ",")
          _extra_info = "#{_extra_info}
CSRF (4,65%): R$ #{csrf}"
        end
        # IRRF (1,5%)
        if total > 666.66
          ir = (total*0.015).round(2).to_s.gsub(".", ",")
          _extra_info = "#{_extra_info}
IRRF (1,5%): R$ #{ir}"
        end

        # config.Impostos = { :pis => 0.0065; :cofins => 0.03; :iss => 0.02; :cprb => 0.02 }
        taxesV = config.Impostos[:pis] + config.Impostos[:cofins] + config.Impostos[:iss] + config.Impostos[:cprb]
        taxesS = (total*taxesV).round(2).to_s.gsub(".", ",")
        taxesV = (taxesV*100).round(2).to_s.gsub(".", ",")

        _extra_info = "#{_extra_info}

Conforme lei federal 12.741/2012 da transparência, total impostos pagos R$ #{taxesS} (#{taxesV}%)"

        servicos.DadosAdicionais _extra_info
      end
      root.Tomador do |tomador|
        tomador.IdentificacaoTomador do |identificacao|
          identificacao.DocIdTomador do |doc|
            formated_cpf_cnpj = format_cpf_cnpj

            #TODO
            doc.CPFCNPJ do |cpfcnpj|
              if (formated_cpf_cnpj.size == 14)
                cpfcnpj.CNPJ formated_cpf_cnpj
              elsif (formated_cpf_cnpj.size == 11)
                cpfcnpj.CPF formated_cpf_cnpj
              else
                raise "Wrong CPF/CNPJ '#{formated_cpf_cnpj}'"
              end
            end
          end # doc
        end # identificacao

        tomador.RazaoSocial name[0..79]
        tomador.Endereco do |endereco|
          endereco.Logradouro address[0..79]
          endereco.Bairro ""
          endereco.Municipio do |municipio|
            municipio.CodigoMunicipio city_info["city_ibge_code"]
          end
          endereco.CodigoPostal do |codPostal|
            codPostal.CEP zipcode.gsub(".", "").gsub("/", "").gsub("-", "").gsub(" ", "")
          end
          endereco.UF state.gsub(" ", "")
        end # endereço
        tomador.Contato do |contato|
          contato.Email email[0..79]
        end

      end # tomador
    end # root
  end

  private

  def format_cpf_cnpj
    cpf_cnpj.gsub(".", "").gsub("/", "").gsub("-", "").gsub("_", "").gsub(" ", "")
  end

  def get_city_info(cep, state = "", cityname = "")
    state.strip!
    cityname.strip!
    cityname = (cityname.downcase == "brasilia") ? "brasília" : cityname
    cityname = (cityname.downcase == "sao paulo") ? "são paulo" : cityname

    city_info = get_cities[state.downcase][cityname.downcase]
    if city_info
      { "city" => city_info["Nome_Município"], "state" => city_info["UF"], "city_ibge_code" => city_info["UF_MUNIC"], "source" => "csv" }
    else
      cep.strip!
      cep = cep.gsub(".", "").gsub("/", "").gsub("-", "").gsub(" ", "")
      response = HTTParty.get("http://api.postmon.com.br/v1/cep/#{cep}")
      resp = response.parsed_response
      { "city" => resp["cidade"], "state" => resp["estado"], "city_ibge_code" => resp["cidade_info"]["codigo_ibge"], "source" => "postmon" }
    end
  end

  def get_cities
    cities ||= load_cities
  end

  def load_cities
    contents =  File.read(filepath('cidades_brasil.csv'))
    lines_parsed = CSV.parse(contents, { :col_sep => "," })
    # UF,UF_MUNIC,Nome_Município

    list = {}
    lines_parsed.each_with_index do |line, i|
      if (i > 0 && !line.empty?)
        list[line[0].downcase] = {} if list[line[0].downcase] == nil
        list[line[0].downcase][line[2].downcase] = { "UF" => line[0], "UF_MUNIC" => line[1], "Nome_Município" => line[2] }
      end
    end
    list
  end

  def filepath(filename)
    File.join(File.dirname(File.expand_path(__FILE__)), filename)
  end

end
