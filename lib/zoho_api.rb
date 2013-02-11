$:.unshift File.join('..', File.dirname(__FILE__), 'lib')

require 'httparty'
require 'rexml/document'
require 'ruby_zoho'
require 'yaml'
require 'api_utils'

module ZohoApi

  include ApiUtils

  class Crm
    NUMBER_OF_RECORDS_TO_GET = 200

    include HTTParty

    #debug_output $stderr

    attr_reader :auth_token

    def initialize(config_file_path)
      @config_file_path = config_file_path
      raise('Zoho configuration file not found', RuntimeError, config_file_path) unless
          File.exist?(config_file_path)
      @params = YAML.load(File.open(config_file_path))
      @auth_token = @params['auth_token']
    end

    def add_contact(c)
      return nil unless c.class == RubyZoho::Crm::Contact
      x = REXML::Document.new
      contacts = x.add_element 'Contacts'
      row = contacts.add_element 'Row', { 'no' => '1'}
      pp c.methods.grep(/\w=$/)
      pp x.to_s
      c
    end

    def add_dummy_contact
      x = REXML::Document.new
      contacts = x.add_element 'Contacts'
      row = contacts.add_element 'row', { 'no' => '1'}
      [
          ['First Name', 'BobDifficultToMatch'],
          ['Last Name', 'SmithDifficultToMatch'],
          ['Email', 'bob@smith.com']
      ].each { |f| add_field(row, f[0], f[1]) }
      r = self.class.post(create_url('Contacts', 'insertRecords'),
                          :query => { :newFormat => 1, :authtoken => @auth_token,
                                      :scope => 'crmapi', :xmlData => x },
                          :headers => { 'Content-length' => '0' })
      raise('Adding contact failed', RuntimeError, r.response.body.to_s) unless r.response.code == '200'
      r.response.code
    end

    def add_record(module_name, fields_values_hash)
      x = REXML::Document.new
      contacts = x.add_element module_name
      row = contacts.add_element 'row', { 'no' => '1'}
      fields_values_hash.each_pair { |k, v| add_field(row, ApiUtils.symbol_to_string(k), v) }
      r = self.class.post(create_url(module_name, 'insertRecords'),
                          :query => { :newFormat => 1, :authtoken => @auth_token,
                                      :scope => 'crmapi', :xmlData => x },
                          :headers => { 'Content-length' => '0' })
      raise('Adding record failed', RuntimeError, r.response.body.to_s) unless r.response.code == '200'
      r.response.code
    end

    def add_field(row, field, value)
      r = (REXML::Element.new 'FL')
      r.attributes['val'] = field
      r.add_text(value)
      row.elements << r
      row
    end

    def self.create_accessor(names)
      names.each do |name|
        n = name
        n = name.to_s if name.class == Symbol
        create_getter(n)
        create_setter(n)
      end
    end

    def self.create_getter(*names)
        names.each do |name|
          define_method("#{name}") { instance_variable_get("@#{name}") }
        end
      names
    end

    def self.create_method(name, &block)
      self.class.send(:define_method, name, &block)
    end

    def self.create_setter(*names)
        names.each do |name|
            define_method("#{name}=") { |val| instance_variable_set("@#{name}", val) }
        end
      names
    end

    def delete_dummy_contact
      c = find_record(
          'Contacts', :email, 'bob@smith.com', [:first_name, :last_name, :email, :company])
      delete_record('Contacts', c[0][:contactid]) unless c == []
    end

    def delete_record(module_name, record_id)
      r = self.class.post(create_url(module_name, 'deleteRecords'),
        :query => { :newFormat => 1, :authtoken => @auth_token,
          :scope => 'crmapi', :id => record_id },
        :headers => { 'Content-length' => '0' })
      raise('Adding contact failed', RuntimeError, r.response.body.to_s) unless r.response.code == '200'
    end

    def create_url(module_name, api_call)
      "https://crm.zoho.com/crm/private/xml/#{module_name}/#{api_call}"
    end

    def fields(module_name)
      record = first(module_name)
      record[0].keys
    end

    def first(module_name)
      some(module_name, 1, 1)
    end

    def find_record(module_name, field, value, columns)
      f = field.class == Symbol ? ApiUtils.symbol_to_string(field) : field
      search_condition = "(#{f}|=|#{value})"
      columns = columns.map { |c| ApiUtils.symbol_to_string(c) }
      select_columns =  "#{module_name}(" + columns.join(',') + ')'
      r = self.class.get(create_url("#{module_name}", 'getSearchRecords'),
         :query => { :newFormat => 2, :authtoken => @auth_token, :scope => 'crmapi',
                     :selectColumns => select_columns,
                     :searchCondition => search_condition })
      x = REXML::Document.new(r.body).elements.to_a("/response/result/#{module_name}/row")
      to_hash(x)
    end

    def some(module_name, index = 1, number_of_records = nil)
      r = self.class.get(create_url(module_name, 'getRecords'),
        :query => { :newFormat => 2, :authtoken => @auth_token, :scope => 'crmapi',
          :fromIndex => index, :toIndex => number_of_records || NUMBER_OF_RECORDS_TO_GET })
      return nil unless r.response.code == '200'
      x = REXML::Document.new(r.body).elements.to_a("/response/result/#{module_name}/row")
      to_hash(x)
    end

    def to_hash(xml_results)
      r = []
      xml_results.each do |e|
        record = {}
        e.elements.to_a.each do |n|
          k = ApiUtils.string_to_symbol(n.attribute('val').to_s.gsub('val=', ''))
          v = n.text == 'null' ? nil : n.text
          record.merge!({ k => v })
        end
        r << record
      end
      return nil if r == []
      r
    end

  end

end
