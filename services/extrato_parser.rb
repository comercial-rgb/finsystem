# frozen_string_literal: true
# services/extrato_parser.rb - Parser de extratos bancários (OFX, CSV, XLSX, PDF)

require 'csv'
require 'bigdecimal'
require 'date'

module FinSystem
  module Services
    class ExtratoParser
      FORMATOS_SUPORTADOS = %w[.ofx .ofc .csv .xlsx .xls .pdf].freeze

      # Retorna array de hashes: { data:, descricao:, valor:, tipo:, referencia: }
      def self.parse(file_path, filename)
        ext = File.extname(filename).downcase
        raise "Formato não suportado: #{ext}. Use: #{FORMATOS_SUPORTADOS.join(', ')}" unless FORMATOS_SUPORTADOS.include?(ext)

        case ext
        when '.ofx', '.ofc'
          parse_ofx(file_path)
        when '.csv'
          parse_csv(file_path)
        when '.xlsx', '.xls'
          parse_xlsx(file_path)
        when '.pdf'
          parse_pdf(file_path)
        end
      end

      # ======================================
      # OFX / OFC  (padrão Febraban BR)
      # ======================================
      def self.parse_ofx(path)
        # Tenta UTF-8 primeiro, cai para ISO-8859-1 (padrão dos bancos BR)
        raw = begin
          File.read(path, encoding: 'utf-8')
        rescue
          File.read(path, encoding: 'iso-8859-1')
               .encode('utf-8', invalid: :replace, undef: :replace)
        end

        # Remove BOM se existir
        raw.sub!("\xEF\xBB\xBF", '')

        transactions = []

        # Split por <STMTTRN> — funciona para SGML (sem fechamento) e XML OFX
        blocks = raw.split(/<STMTTRN>/i)
        blocks.shift  # descarta cabeçalho antes do primeiro bloco

        blocks.each do |block|
          # Para XML OFX: corta no </STMTTRN>
          block = block.split(/<\/STMTTRN>/i).first || block

          dtposted = extract_ofx_field(block, 'DTPOSTED')
          amount   = extract_ofx_field(block, 'TRNAMT')
          memo     = extract_ofx_field(block, 'MEMO') ||
                     extract_ofx_field(block, 'NAME') ||
                     'Importado OFX'
          fitid    = extract_ofx_field(block, 'FITID')

          next unless dtposted && amount

          # DTPOSTED pode ser: 20250401, 20250401120000, 20250401120000[-3:BRT]
          date = parse_date(dtposted.gsub(/[^0-9].*$/, '')[0..7])
          next unless date

          valor = amount.strip.gsub(',', '.').to_f
          tipo  = valor >= 0 ? 'receita' : 'despesa'

          transactions << {
            data:       date,
            descricao:  sanitize(memo),
            valor:      valor.abs,
            tipo:       tipo,
            referencia: fitid
          }
        end

        transactions
      end

      def self.extract_ofx_field(text, field)
        # SGML: <FIELD>valor\n  ou  XML: <FIELD>valor</FIELD>
        m = text.match(/<#{field}>\s*([^\r\n<]+)/i)
        m&.captures&.first&.strip
      end

      # ======================================
      # CSV  (Nubank, XP, Inter, etc.)
      # ======================================
      def self.parse_csv(path)
        content = begin
          File.read(path, encoding: 'utf-8')
        rescue
          File.read(path, encoding: 'iso-8859-1').encode('utf-8', invalid: :replace, undef: :replace)
        end

        # Remove BOM se existir
        content.sub!("\xEF\xBB\xBF", '')

        sep = content.include?(';') ? ';' : ','

        rows = CSV.parse(content, col_sep: sep, headers: true, skip_blanks: true)
        headers = rows.headers.map { |h| h&.to_s&.downcase&.strip }

        date_col  = detect_col(headers, /data|date|dt\.?/i)
        desc_col  = detect_col(headers, /descri|hist[oó]rico?|memo|lançament|estabelec|nome/i)
        value_col = detect_col(headers, /valor|value|amount|quantia/i)
        type_col  = detect_col(headers, /\btipo\b|type|\bdc\b|natureza/i)
        # Nubank tem colunas separadas: "valor" (positivo=compra)
        # Inter tem "Valor" positivo p/ crédito, negativo p/ débito

        transactions = []
        rows.each do |row|
          data_str = row[date_col]&.strip
          next if data_str.nil? || data_str.empty?

          date = parse_date(data_str)
          next unless date

          valor_raw = row[value_col]&.strip || '0'
          # Normaliza: remove pontos de milhar, troca vírgula decimal
          valor_float = parse_valor(valor_raw)
          next if valor_float == 0

          tipo = if type_col
            v = row[type_col].to_s.downcase
            (v.match?(/^c|cr[eé]d|receit|entra/i)) ? 'receita' : 'despesa'
          else
            valor_float >= 0 ? 'receita' : 'despesa'
          end

          transactions << {
            data: date,
            descricao: sanitize(row[desc_col]&.strip || 'Importado CSV'),
            valor: valor_float.abs,
            tipo: tipo
          }
        end

        transactions
      end

      # ======================================
      # XLSX / XLS  (Bradesco, Itaú, BB, etc.)
      # ======================================
      def self.parse_xlsx(path)
        require 'roo'
        xlsx = Roo::Spreadsheet.open(path)
        sheet = xlsx.sheet(0)

        # Encontrar linha de cabeçalho (primeiras 5 linhas)
        header_row = nil
        (1..5).each do |i|
          row = sheet.row(i).map { |c| c&.to_s&.downcase&.strip }
          if row.any? { |c| c&.match?(/data|valor|histor|descri/i) }
            header_row = i
            break
          end
        end
        header_row ||= 1

        headers = sheet.row(header_row).map { |c| c&.to_s&.downcase&.strip }

        date_idx  = headers.find_index { |h| h&.match?(/^data|^dt\.?/i) }
        desc_idx  = headers.find_index { |h| h&.match?(/hist[oó]r|descri|lançament|estabelec/i) }
        value_idx = headers.find_index { |h| h&.match?(/^valor$|^value$|^amount$/i) }
        type_idx  = headers.find_index { |h| h&.match?(/\btipo\b|\bdc\b|natureza/i) }

        # Fallback: última coluna numérica como valor
        value_idx ||= headers.rindex { |h| h&.match?(/\d|r\$|valor|cr[eé]d|d[eé]b/i) }

        transactions = []
        ((header_row + 1)..sheet.last_row).each do |i|
          row = sheet.row(i)
          next if row.all?(&:nil?)

          # Data
          date_raw = date_idx ? row[date_idx] : nil
          date = case date_raw
                 when Date       then date_raw
                 when DateTime   then date_raw.to_date
                 when Float, Integer then
                   # Excel serial date
                   Date.new(1899, 12, 30) + date_raw.to_i
                 when String     then parse_date(date_raw.strip)
                 end
          next unless date

          # Valor
          valor_raw = value_idx ? row[value_idx] : nil
          valor_float = case valor_raw
                        when Numeric then valor_raw.to_f
                        when String  then parse_valor(valor_raw)
                        else 0.0
                        end
          next if valor_float == 0

          # Tipo
          tipo = if type_idx
            v = row[type_idx].to_s.downcase
            v.match?(/^c|cr[eé]d|receit/i) ? 'receita' : 'despesa'
          else
            valor_float >= 0 ? 'receita' : 'despesa'
          end

          desc = desc_idx ? row[desc_idx]&.to_s&.strip : nil
          transactions << {
            data: date,
            descricao: sanitize(desc || 'Importado Excel'),
            valor: valor_float.abs,
            tipo: tipo
          }
        end

        transactions
      end

      # ======================================
      # PDF  (melhor esforço — padrão BR)
      # ======================================
      def self.parse_pdf(path)
        require 'pdf/reader'
        reader = PDF::Reader.new(path)
        text = reader.pages.map(&:text).join("\n")

        transactions = []

        # Padrão comum: DD/MM/YYYY <descrição> <valor> [D|C]
        # Ex: "15/04/2025  COMPRA PIX RECEBIDO  1.500,00 C"
        text.each_line do |line|
          line = line.strip
          next if line.empty?

          m = line.match(/\A(\d{2}\/\d{2}\/\d{2,4})\s+(.+?)\s+([\d.,]+)\s*([DC])?\s*\z/i)
          next unless m

          date = parse_date(m[1])
          next unless date

          valor = parse_valor(m[3])
          next if valor == 0

          dc   = m[4]&.upcase
          tipo = (dc == 'C') ? 'receita' : 'despesa'

          transactions << {
            data: date,
            descricao: sanitize(m[2]),
            valor: valor.abs,
            tipo: tipo
          }
        end

        # Se o padrão acima não encontrou nada, tentar formato alternativo
        if transactions.empty?
          text.scan(/(\d{2}\/\d{2}\/\d{2,4})\s+([\d.,]+)/) do |date_str, value_str|
            date  = parse_date(date_str)
            valor = parse_valor(value_str)
            next unless date && valor > 0

            transactions << {
              data: date,
              descricao: 'Importado PDF',
              valor: valor,
              tipo: 'despesa'  # conservador: marcar como despesa para revisão
            }
          end
        end

        transactions
      end

      # ======================================
      # UTILITÁRIOS
      # ======================================

      def self.parse_date(str)
        return nil unless str
        s = str.to_s.strip

        # YYYYMMDD (OFX)
        if s.match?(/\A\d{8}\z/)
          return Date.strptime(s, '%Y%m%d') rescue nil
        end

        # Tenta formatos comuns
        %w[%d/%m/%Y %d/%m/%y %Y-%m-%d %m/%d/%Y %d-%m-%Y %Y%m%d].each do |fmt|
          d = Date.strptime(s, fmt) rescue nil
          return d if d
        end

        Date.parse(s) rescue nil
      end

      def self.parse_valor(str)
        return 0.0 unless str
        s = str.to_s.strip.gsub(/[R$\s]/, '')

        # Formato BR: 1.234,56 → negativo se começar com -
        negativo = s.start_with?('-')
        s = s.delete('-')

        # Detecta se usa vírgula como decimal ou ponto
        if s.match?(/,\d{1,2}\z/)
          # BR: 1.234,56
          s = s.gsub('.', '').gsub(',', '.')
        else
          # US ou inteiro: 1234.56 ou 1234
          s = s.gsub(',', '')
        end

        v = s.to_f
        negativo ? -v : v
      end

      def self.detect_col(headers, pattern)
        headers.find { |h| h&.match?(pattern) }
      end

      def self.sanitize(str)
        return '' unless str
        str.to_s.encode('utf-8', invalid: :replace, undef: :replace, replace: '')
           .gsub(/\s+/, ' ')
           .strip[0..255]
      end
    end
  end
end
