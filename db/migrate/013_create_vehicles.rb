# db/migrate/XXXXXX_create_vehicles.rb
# Vehículos de la flota

class CreateVehicles < ActiveRecord::Migration[8.0]
  def change
    create_table :vehicles do |t|
      # Relación con tenant
      t.bigint :tenant_id, null: false

      # Relación con nodo organizacional (opcional)
      t.bigint :organizational_node_id

      # Identificación del vehículo
      t.string :name, null: false, limit: 255
      t.string :license_plate, null: false, limit: 20
      t.string :vin, limit: 50 # Vehicle Identification Number
      t.string :fleet_number, limit: 50

      # Tipo y marca
      t.string :vehicle_type, limit: 50 # car, truck, van, motorcycle, etc.
      t.string :make, limit: 100 # Marca
      t.string :model, limit: 100 # Modelo
      t.integer :year

      # Estado y mantenimiento
      t.string :status, limit: 20, default: 'active', null: false
      t.date :purchase_date
      t.date :registration_expires_at
      t.date :insurance_expires_at
      t.date :last_maintenance_date
      t.integer :odometer # Kilometraje actual

      # Características
      t.string :color, limit: 50
      t.string :fuel_type, limit: 20 # gasoline, diesel, electric, hybrid
      t.decimal :fuel_capacity, precision: 10, scale: 2
      t.integer :passenger_capacity

      # Metadata y configuración
      t.jsonb :metadata, default: {}
      t.jsonb :specifications, default: {}

      # Auditoría
      t.bigint :created_by
      t.datetime :deleted_at
      t.bigint :deleted_by

      t.timestamps
    end

    # Índices
    add_index :vehicles, :tenant_id
    add_index :vehicles, :organizational_node_id
    add_index :vehicles, [ :tenant_id, :license_plate ],
              unique: true,
              where: 'deleted_at IS NULL'
    add_index :vehicles, [ :tenant_id, :fleet_number ],
              unique: true,
              where: 'fleet_number IS NOT NULL AND deleted_at IS NULL'
    add_index :vehicles, :status
    add_index :vehicles, :vehicle_type
    add_index :vehicles, :deleted_at

    # Foreign keys
    add_foreign_key :vehicles, :tenants, on_delete: :cascade
    add_foreign_key :vehicles, :organizational_nodes, on_delete: :nullify
    add_foreign_key :vehicles, :users, column: :created_by, on_delete: :nullify
  end
end
