class CreateVersions < ActiveRecord::Migration[8.0]
  # Esta migración es compatible con todas las versiones de PaperTrail
  TEXT_BYTES = 1_073_741_823 # Máximo para PostgreSQL text column

  def change
    create_table :versions do |t|
      # Información del modelo versionado
      t.string   :item_type, null: false, index: true
      t.bigint   :item_id,   null: false, index: true

      # Tipo de evento (create, update, destroy)
      t.string   :event, null: false

      # Usuario que realizó el cambio (whodunnit)
      # Guardamos como string para flexibilidad (puede ser ID o email)
      t.string   :whodunnit

      # Estado del objeto (serializado en JSON)
      # - object: estado anterior (antes del cambio)
      # - object_changes: qué cambió específicamente
      t.jsonb    :object
      t.jsonb    :object_changes

      # Metadata adicional del contexto
      # Aquí guardaremos: tenant_id, ip_address, user_agent, etc.
      t.jsonb    :metadata

      # Timestamp del cambio
      t.datetime :created_at, null: false
    end

    # Índices para mejorar performance de queries

    # Índice compuesto para buscar versiones de un item específico
    add_index :versions, [ :item_type, :item_id ],
              name: 'index_versions_on_item_type_and_item_id'

    # Índice para buscar por usuario
    add_index :versions, :whodunnit,
              name: 'index_versions_on_whodunnit'

    # Índice para buscar por tipo de evento
    add_index :versions, :event,
              name: 'index_versions_on_event'

    # Índice para buscar por fecha
    add_index :versions, :created_at,
              name: 'index_versions_on_created_at'

    # Índice GIN para búsquedas en JSONB (PostgreSQL)
    # Permite búsquedas eficientes en metadata
    add_index :versions, :metadata,
              using: :gin,
              name: 'index_versions_on_metadata'

    # Índice para tenant_id en metadata (multitenancy)
    # Esto permite filtrar versiones por tenant de forma eficiente
    add_index :versions, "(metadata->>'tenant_id')",
              name: 'index_versions_on_tenant_id'
  end
end
