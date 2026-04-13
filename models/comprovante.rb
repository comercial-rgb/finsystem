# frozen_string_literal: true
# models/comprovante.rb - Model de comprovantes/anexos

require 'digest'
require 'fileutils'

module FinSystem
  module Models
    class Comprovante
      def self.db
        FinSystem::Database.db
      end

      def self.table
        db[:comprovantes]
      end

      # Upload e salvar comprovante
      def self.salvar(movimentacao_id, usuario_id, arquivo)
        return nil unless arquivo && arquivo[:tempfile]

        # Validar tipo de arquivo
        tipo = arquivo[:type]
        return { error: 'Tipo de arquivo não permitido' } unless Config::ALLOWED_FILE_TYPES.include?(tipo)

        # Validar tamanho
        size = arquivo[:tempfile].size
        return { error: 'Arquivo excede 10MB' } if size > Config::MAX_UPLOAD_SIZE

        # Gerar nome único
        ext = File.extname(arquivo[:filename])
        nome_unico = "#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{SecureRandom.hex(8)}#{ext}"

        # Criar diretório do mês
        dir = File.join(Config::UPLOAD_DIR, Date.today.strftime('%Y/%m'))
        FileUtils.mkdir_p(dir)

        caminho = File.join(dir, nome_unico)

        # Salvar arquivo
        File.open(caminho, 'wb') { |f| f.write(arquivo[:tempfile].read) }

        # Hash SHA256 para integridade
        hash = Digest::SHA256.file(caminho).hexdigest

        # Registrar no banco
        table.insert(
          movimentacao_id: movimentacao_id,
          usuario_id: usuario_id,
          nome_arquivo: nome_unico,
          nome_original: arquivo[:filename],
          tipo_arquivo: ext.delete('.'),
          tamanho_bytes: size,
          caminho_arquivo: caminho,
          hash_arquivo: hash
        )
      end

      # Buscar comprovantes de uma movimentação
      def self.por_movimentacao(movimentacao_id)
        table.where(movimentacao_id: movimentacao_id).order(:created_at).all
      end

      # Excluir comprovante
      def self.excluir(id)
        comp = table.where(id: id).first
        if comp
          begin
            File.delete(comp[:caminho_arquivo]) if File.exist?(comp[:caminho_arquivo])
          rescue Errno::ENOENT; end
          table.where(id: id).delete
        end
      end

      # Verificar integridade
      def self.verificar_integridade(id)
        comp = table.where(id: id).first
        return false unless comp && File.exist?(comp[:caminho_arquivo])

        Digest::SHA256.file(comp[:caminho_arquivo]).hexdigest == comp[:hash_arquivo]
      end
    end
  end
end
