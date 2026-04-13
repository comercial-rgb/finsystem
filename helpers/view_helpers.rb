# frozen_string_literal: true
# helpers/view_helpers.rb - Helpers para formatação nas views

module FinSystem
  module Helpers
    module ViewHelpers
      # Formatar valor monetário (BRL = R$ 1.234,56 | USD = $ 1,234.56)
      def fmt_moeda(valor, moeda = 'BRL')
        moeda = moeda.to_s
        moeda = 'BRL' if moeda.empty?
        simbolo = Config::MOEDAS[moeda] || 'R$'

        if valor.nil? || (valor.respond_to?(:zero?) && valor.zero?)
          return moeda == 'USD' ? "#{simbolo} 0.00" : "#{simbolo} 0,00"
        end

        v = valor.to_f
        if moeda == 'USD'
          # Formato americano: $ 1,234.56
          parts = format('%.2f', v).split('.')
          parts[0] = parts[0].gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')
          "#{simbolo} #{parts.join('.')}"
        else
          # Formato brasileiro: R$ 1.234,56
          "#{simbolo} #{format('%.2f', v).gsub('.', ',').gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1.')}"
        end
      end

      # Formatar data
      def fmt_data(data)
        return '-' unless data

        data = Date.parse(data.to_s) unless data.is_a?(Date)
        data.strftime('%d/%m/%Y')
      end

      # Formatar data e hora
      def fmt_datetime(dt)
        return '-' unless dt

        dt.strftime('%d/%m/%Y %H:%M')
      end

      # Nome do mês
      def nome_mes(num)
        meses = %w[_ Janeiro Fevereiro Março Abril Maio Junho Julho Agosto Setembro Outubro Novembro Dezembro]
        meses[num.to_i] || num.to_s
      end

      # Badge de status
      def badge_status(status)
        cores = {
          'confirmado' => 'bg-green-100 text-green-800',
          'pendente'   => 'bg-yellow-100 text-yellow-800',
          'cancelado'  => 'bg-red-100 text-red-800',
          'conciliado' => 'bg-blue-100 text-blue-800'
        }
        classe = cores[status] || 'bg-gray-100 text-gray-800'
        "<span class='px-2 py-1 text-xs font-medium rounded-full #{classe}'>#{status&.capitalize}</span>"
      end

      # Badge de tipo (receita/despesa)
      def badge_tipo(tipo)
        if tipo == 'receita'
          "<span class='px-2 py-1 text-xs font-bold rounded-full bg-emerald-100 text-emerald-800'>▲ Receita</span>"
        else
          "<span class='px-2 py-1 text-xs font-bold rounded-full bg-red-100 text-red-800'>▼ Despesa</span>"
        end
      end

      # Cor do valor
      def cor_valor(tipo)
        tipo == 'receita' ? 'text-emerald-600' : 'text-red-600'
      end

      # Prefixo do valor
      def prefixo_valor(tipo)
        tipo == 'receita' ? '+' : '-'
      end

      # Percentual formatado (formato brasileiro: vírgula como decimal)
      def fmt_percentual(valor)
        return '0%' if valor.nil?

        "#{format('%.1f', valor).gsub('.', ',')}%"
      end

      # Formatar valor para campo de input (formato brasileiro por padrão)
      def fmt_valor_input(valor, moeda = 'BRL')
        return '0,00' if valor.nil? || (valor.respond_to?(:zero?) && valor.zero?)

        if moeda.to_s == 'USD'
          parts = format('%.2f', valor.to_f).split('.')
          parts[0] = parts[0].gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')
          parts.join('.')
        else
          format('%.2f', valor.to_f).gsub('.', ',').gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1.')
        end
      end

      # Truncar texto
      def truncar(texto, max = 50)
        return '' unless texto

        texto.length > max ? "#{texto[0..max]}..." : texto
      end

      # Nível de acesso legível
      def label_acesso(nivel)
        Config::ACCESS_LEVELS.dig(nivel, :label) || nivel
      end

      # Meses para select
      def meses_select
        (1..12).map { |m| [m, nome_mes(m)] }
      end

      # Anos para select (últimos 3 + atual + próximo)
      def anos_select
        ano = Date.today.year
        ((ano - 3)..(ano + 1)).to_a.reverse
      end

      # Data atual formatada
      def hoje
        Date.today.strftime('%Y-%m-%d')
      end

      def mes_atual
        Date.today.month
      end

      def ano_atual
        Date.today.year
      end
    end
  end
end
