# frozen_string_literal: true
# models/empresa.rb - Model de empresas do grupo

module FinSystem
  module Models
    class Empresa
      def self.db
        FinSystem::Database.db
      end

      def self.table
        db[:empresas]
      end

      def self.todas
        table.where(ativo: true).order(:nome_fantasia).all
      end

      def self.find(id)
        table.where(id: id).first
      end

      def self.criar(params)
        table.insert(
          razao_social: params[:razao_social],
          nome_fantasia: params[:nome_fantasia],
          cnpj_ein: params[:cnpj_ein],
          pais: params[:pais] || 'BR',
          estado: params[:estado],
          cidade: params[:cidade],
          endereco: params[:endereco],
          regime_tributario: params[:regime_tributario]
        )
      end

      def self.atualizar(id, params)
        update_data = {}
        %i[razao_social nome_fantasia cnpj_ein pais estado cidade endereco regime_tributario].each do |f|
          update_data[f] = params[f] if params[f]
        end
        update_data[:updated_at] = Time.now
        table.where(id: id).update(update_data)
      end

      # Sócios da empresa
      def self.socios(empresa_id)
        db[:socios].where(empresa_id: empresa_id, ativo: true).order(:nome).all
      end

      def self.atualizar_socio(id, params)
        update_data = {}
        update_data[:nome] = params[:nome] if params[:nome]
        update_data[:cpf_ssn] = params[:cpf_ssn] if params[:cpf_ssn]
        update_data[:percentual_participacao] = BigDecimal(params[:percentual_participacao].to_s) if params[:percentual_participacao]
        update_data[:tipo] = params[:tipo] if params[:tipo]
        db[:socios].where(id: id).update(update_data)
      end

      def self.criar_socio(params)
        db[:socios].insert(
          empresa_id: params[:empresa_id].to_i,
          nome: params[:nome],
          cpf_ssn: params[:cpf_ssn],
          percentual_participacao: BigDecimal(params[:percentual_participacao].to_s),
          tipo: params[:tipo] || 'socio'
        )
      end

      # Contas bancárias da empresa
      def self.contas_bancarias(empresa_id)
        db[:contas_bancarias].where(empresa_id: empresa_id, ativo: true).order(:banco).all
      end

      # Todas as contas (para dropdown)
      def self.todas_contas
        db[:contas_bancarias].where(Sequel[:contas_bancarias][:ativo] => true)
          .left_join(:empresas, Sequel[:empresas][:id] => Sequel[:contas_bancarias][:empresa_id])
          .select_all(:contas_bancarias)
          .select_append(Sequel[:empresas][:nome_fantasia].as(:empresa_nome))
          .order(Sequel[:empresas][:nome_fantasia], Sequel[:contas_bancarias][:banco])
          .all
      end

      # Distribuição de lucro por sócio
      def self.distribuicao_lucro(empresa_id, lucro_total)
        socios_empresa = socios(empresa_id)
        socios_empresa.map do |s|
          {
            socio: s,
            percentual: s[:percentual_participacao],
            valor: (lucro_total * s[:percentual_participacao] / 100).round(2)
          }
        end
      end
    end
  end
end
