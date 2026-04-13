# frozen_string_literal: true
# services/validation.rb - Validação de dados no backend

module FinSystem
  module Services
    class Validation
      # Validar movimentação financeira
      def self.validate_movimentacao(params)
        errors = []
        errors << 'Empresa é obrigatória' if params[:empresa_id].nil? || params[:empresa_id].to_s.empty?
        errors << 'Conta bancária é obrigatória' if params[:conta_bancaria_id].nil? || params[:conta_bancaria_id].to_s.empty?
        errors << 'Tipo é obrigatório (receita/despesa)' if params[:tipo].nil? || params[:tipo].to_s.empty?
        errors << 'Data é obrigatória' if params[:data_movimentacao].nil? || params[:data_movimentacao].to_s.empty?
        errors << 'Descrição é obrigatória' if params[:descricao].nil? || params[:descricao].to_s.strip.empty?

        valor = params[:valor_bruto].to_s.gsub(',', '.').to_f
        errors << 'Valor bruto deve ser maior que zero' if valor <= 0

        begin
          Date.parse(params[:data_movimentacao]) if params[:data_movimentacao]
        rescue ArgumentError
          errors << 'Data inválida'
        end

        errors
      end

      # Validar antecipação
      def self.validate_antecipacao(params)
        errors = validate_movimentacao(params)
        
        valor_original = params[:valor_original_faturamento].to_s.gsub(',', '.').to_f
        valor_antecipado = params[:valor_antecipado].to_s.gsub(',', '.').to_f

        errors << 'Valor original do faturamento é obrigatório' if valor_original <= 0
        errors << 'Valor antecipado é obrigatório' if valor_antecipado <= 0
        errors << 'Valor antecipado não pode ser maior que o valor original' if valor_antecipado > valor_original
        errors << 'Fornecedor é obrigatório para antecipação' if params[:fornecedor_id].nil? || params[:fornecedor_id].to_s.empty?

        errors
      end

      # Validar cliente
      def self.validate_cliente(params)
        errors = []
        errors << 'Nome é obrigatório' if params[:nome].nil? || params[:nome].to_s.strip.empty?
        
        if params[:email] && !params[:email].empty?
          errors << 'Email inválido' unless params[:email] =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
        end

        errors
      end

      # Validar fornecedor
      def self.validate_fornecedor(params)
        errors = []
        errors << 'Nome é obrigatório' if params[:nome].nil? || params[:nome].to_s.strip.empty?
        
        if params[:email] && !params[:email].empty?
          errors << 'Email inválido' unless params[:email] =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
        end

        errors
      end

      # Validar empresa
      def self.validate_empresa(params)
        errors = []
        errors << 'Razão Social é obrigatória' if params[:razao_social].nil? || params[:razao_social].to_s.strip.empty?
        errors << 'Nome Fantasia é obrigatório' if params[:nome_fantasia].nil? || params[:nome_fantasia].to_s.strip.empty?
        errors << 'CNPJ/EIN é obrigatório' if params[:cnpj_ein].nil? || params[:cnpj_ein].to_s.strip.empty?
        errors
      end

      # Validar usuário
      def self.validate_usuario(params, is_update: false)
        errors = []
        errors << 'Nome é obrigatório' if params[:nome].nil? || params[:nome].to_s.strip.empty?
        errors << 'Email é obrigatório' if params[:email].nil? || params[:email].to_s.strip.empty?

        if params[:email] && !params[:email].empty?
          errors << 'Email inválido' unless params[:email] =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i
        end

        unless is_update
          errors << 'Senha é obrigatória' if params[:senha].nil? || params[:senha].to_s.empty?
          errors << 'Senha deve ter no mínimo 6 caracteres' if params[:senha] && params[:senha].length < 6
        end

        if is_update && params[:senha] && !params[:senha].empty?
          errors << 'Senha deve ter no mínimo 6 caracteres' if params[:senha].length < 6
        end

        errors
      end

      # Validar movimentação pessoal
      def self.validate_pessoal(params)
        errors = []
        errors << 'Tipo é obrigatório' if params[:tipo].nil? || params[:tipo].to_s.empty?
        errors << 'Data é obrigatória' if params[:data_movimentacao].nil? || params[:data_movimentacao].to_s.empty?
        errors << 'Descrição é obrigatória' if params[:descricao].nil? || params[:descricao].to_s.strip.empty?

        valor = params[:valor].to_s.gsub(',', '.').to_f
        errors << 'Valor deve ser maior que zero' if valor <= 0

        errors
      end

      # Validar sócio
      def self.validate_socio(params)
        errors = []
        errors << 'Nome é obrigatório' if params[:nome].nil? || params[:nome].to_s.strip.empty?
        
        pct = params[:percentual_participacao].to_s.gsub(',', '.').to_f
        errors << 'Percentual de participação inválido' if pct <= 0 || pct > 100

        errors
      end
    end
  end
end
