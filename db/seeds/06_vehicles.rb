# frozen_string_literal: true

# db/seeds/06_vehicles.rb
# Vehículos de flota con diferentes estados y configuraciones

puts "\n🚗 Creating Vehicles..."

# Solo para tenants con estructura organizacional
tenants_with_vehicles = [
  Tenant.find_by(slug: 'tech-startup'),
  Tenant.find_by(slug: 'global-logistics'),
  Tenant.find_by(slug: 'enterprise-mega')
].compact

# Marcas y modelos comunes
VEHICLE_DATA = {
  car: {
    makes: [ 'Toyota', 'Volkswagen', 'Ford', 'Seat', 'Renault' ],
    models: [ 'Corolla', 'Golf', 'Focus', 'Ibiza', 'Clio' ],
    fuel_types: [ 'gasoline', 'diesel', 'hybrid' ],
    passenger_capacity: 5
  },
  truck: {
    makes: [ 'Mercedes', 'Volvo', 'MAN', 'Iveco', 'Scania' ],
    models: [ 'Actros', 'FH', 'TGX', 'Stralis', 'R-Series' ],
    fuel_types: [ 'diesel' ],
    passenger_capacity: 2
  },
  van: {
    makes: [ 'Mercedes', 'Ford', 'Fiat', 'Peugeot', 'Citroën' ],
    models: [ 'Sprinter', 'Transit', 'Ducato', 'Boxer', 'Jumper' ],
    fuel_types: [ 'diesel', 'electric' ],
    passenger_capacity: 3
  }
}

COLORS = [ 'White', 'Black', 'Silver', 'Blue', 'Red', 'Gray' ]
STATUSES = [ 'active', 'inactive', 'maintenance' ]

tenants_with_vehicles.each do |tenant|
  puts "\n  Creating vehicles for: #{tenant.name}"

  ActsAsTenant.with_tenant(tenant) do
    # Obtener nodos que permiten vehículos
    nodes_with_vehicles = OrganizationalNode.joins(:level)
      .where(organizational_node_levels: { allows_vehicles: true })
      .to_a

    next if nodes_with_vehicles.empty?

    vehicle_count = case tenant.slug
    when 'tech-startup'
      5  # Pocos vehículos
    when 'global-logistics'
      25 # Flota mediana
    when 'enterprise-mega'
      50 # Flota grande
    else
      10
    end

    vehicle_count.times do |i|
      # Tipo de vehículo aleatorio
      vehicle_type = VEHICLE_DATA.keys.sample
      vehicle_info = VEHICLE_DATA[vehicle_type]

      make = vehicle_info[:makes].sample
      model = vehicle_info[:models].sample
      fuel_type = vehicle_info[:fuel_types].sample
      color = COLORS.sample
      status = STATUSES.sample

      # Matrícula española aleatoria
      license_plate = "#{rand(1000..9999)}#{('A'..'Z').to_a.sample(3).join}"

      # Año aleatorio (últimos 10 años)
      year = rand(2015..2024)

      # Nodo aleatorio
      node = nodes_with_vehicles.sample

      # Kilometraje basado en año
      base_km = (2024 - year) * rand(15000..25000)
      odometer = base_km + rand(0..10000)

      vehicle = Vehicle.create_with(
        name: "#{make} #{model} #{license_plate}",
        vehicle_type: vehicle_type.to_s,
        make: make,
        model: model,
        year: year,
        color: color,
        license_plate: license_plate,
        vin: "VIN#{SecureRandom.hex(8).upcase}",
        fleet_number: "FL-#{tenant.slug[0..2].upcase}-#{(i + 1).to_s.rjust(4, '0')}",
        status: status,
        fuel_type: fuel_type,
        fuel_capacity: vehicle_type == :truck ? 300 : (vehicle_type == :van ? 80 : 50),
        passenger_capacity: vehicle_info[:passenger_capacity],
        odometer: odometer,
        purchase_date: Date.new(year, rand(1..12), rand(1..28)),
        registration_expires_at: Date.new(2025, rand(1..12), rand(1..28)),
        insurance_expires_at: Date.new(2025, rand(1..12), rand(1..28)),
        last_maintenance_date: rand(1..6).months.ago,
        organizational_node: node,
        metadata: {
          gps_enabled: [ true, false ].sample,
          telematics_unit: [ 'Unit-A', 'Unit-B', 'Unit-C', nil ].sample,
          tags: [ 'priority', 'long-distance', 'urban', 'backup' ].sample(rand(0..2))
        },
        specifications: {
          engine: "#{rand(90..300)}HP",
          transmission: [ 'Manual', 'Automatic' ].sample,
          doors: vehicle_type == :truck ? 2 : rand(3..5),
          load_capacity_kg: vehicle_type == :truck ? rand(10000..25000) :
                           (vehicle_type == :van ? rand(1000..3000) : nil)
        }
      ).find_or_create_by!(tenant: tenant)

      # Algunos vehículos con registro próximo a expirar
      if i % 10 == 0
        vehicle.update_column(:registration_expires_at, 15.days.from_now)
      end

      # Algunos con seguro próximo a expirar
      if i % 12 == 0
        vehicle.update_column(:insurance_expires_at, 20.days.from_now)
      end

      # Algunos que necesitan mantenimiento
      if i % 8 == 0
        vehicle.update_columns(
          last_maintenance_date: 8.months.ago,
          status: 'maintenance'
        )
      end
    end

    puts "    ✓ Created #{vehicle_count} vehicles"

    # Estadísticas del tenant
    total = Vehicle.count
    by_type = Vehicle.group(:vehicle_type).count
    by_status = Vehicle.group(:status).count

    puts "      By Type: #{by_type.map { |k, v| "#{k}: #{v}" }.join(', ')}"
    puts "      By Status: #{by_status.map { |k, v| "#{k}: #{v}" }.join(', ')}"
  end
end

# ============================================
# RESUMEN
# ============================================

puts "\n  📊 Vehicles Summary:"

# Usar unscoped para contar sin filtros de tenant
ActsAsTenant.without_tenant do
  total_vehicles = Vehicle.unscoped.count
  puts "    - Total Vehicles: #{total_vehicles}"

  puts "    - By Type:"
  Vehicle.unscoped.group(:vehicle_type).count.each do |type, count|
    puts "      - #{type.to_s.capitalize}: #{count}"
  end

  puts "    - By Status:"
  Vehicle.unscoped.group(:status).count.each do |status, count|
    puts "      - #{status.capitalize}: #{count}"
  end

  puts "    - Expiring Soon:"
  puts "      - Registration: #{Vehicle.unscoped.where('registration_expires_at BETWEEN ? AND ?', Date.current, 30.days.from_now).count}"
  puts "      - Insurance: #{Vehicle.unscoped.where('insurance_expires_at BETWEEN ? AND ?', Date.current, 30.days.from_now).count}"

  puts "\n  🚗 Sample Vehicles:"
  Vehicle.unscoped.limit(5).each do |v|
    ActsAsTenant.with_tenant(v.tenant) do
      puts "    #{v.fleet_number}: #{v.name} (#{v.status})"
      puts "      - Tenant: #{v.tenant.name}"
      puts "      - Location: #{v.organization_path}"
      puts "      - #{v.odometer.to_i} km, #{v.year}, #{v.fuel_type}"
    end
  end
end
