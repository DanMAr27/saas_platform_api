# db/seeds/06_vehicles.rb
# Vehículos con datos enriquecidos y variedad de estados

puts "\n🚗 Creating Vehicles..."

tenants_with_vehicles = [
  Tenant.find_by(slug: 'tech-startup'),
  Tenant.find_by(slug: 'global-logistics'),
  Tenant.find_by(slug: 'enterprise-mega')
].compact

# ============================================
# DATOS DE VEHÍCULOS EXTENDIDO
# ============================================

VEHICLE_CATALOG = {
  car: {
    makes: {
      'Toyota' => [ 'Corolla', 'Auris', 'Yaris', 'Prius' ],
      'Volkswagen' => [ 'Golf', 'Passat', 'Polo', 'Tiguan' ],
      'Ford' => [ 'Focus', 'Mondeo', 'Fiesta', 'Kuga' ],
      'Seat' => [ 'Ibiza', 'León', 'Tarraco', 'Arona' ],
      'Renault' => [ 'Clio', 'Mégane', 'Captur', 'Espace' ]
    },
    fuel_types: [ 'gasoline', 'diesel', 'hybrid', 'electric' ],
    passenger_capacity: 5,
    base_price: 15000
  },
  truck: {
    makes: {
      'Mercedes' => [ 'Actros 1840', 'Actros 2545', 'Sprinter 311' ],
      'Volvo' => [ 'FH16', 'FH13', 'FM330' ],
      'MAN' => [ 'TGX 28.440', 'TGX 33.480', 'TGX 18.320' ],
      'Iveco' => [ 'Stralis 450', 'Stralis 380', 'Daily' ],
      'Scania' => [ 'R450', 'R490', 'G450' ]
    },
    fuel_types: [ 'gasoline', 'diesel', 'hybrid', 'electric' ],
    passenger_capacity: 2,
    base_price: 80000
  },
  van: {
    makes: {
      'Mercedes' => [ 'Sprinter 314', 'Sprinter 319', 'Vito 119' ],
      'Ford' => [ 'Transit 290S', 'Transit 350L', 'Transit 470' ],
      'Fiat' => [ 'Ducato 30', 'Ducato 35', 'Ducato 40' ],
      'Peugeot' => [ 'Boxer 330', 'Boxer 435', 'Expert' ],
      'Citroën' => [ 'Jumper 330', 'Jumper 435', 'Berlingo' ]
    },
    fuel_types: [ 'gasoline', 'diesel', 'hybrid', 'electric' ],
    passenger_capacity: 3,
    base_price: 35000
  },
  motorcycle: {
    makes: {
      'BMW' => [ 'R 1250 GS', 'F 750 GS' ],
      'Yamaha' => [ 'T-Max', 'XMax' ],
      'Honda' => [ 'PCX', 'SH' ],
      'Piaggio' => [ 'MP3 300', 'Beverly' ]
    },
    fuel_types: [ 'gasoline', 'diesel', 'hybrid', 'electric' ],
    passenger_capacity: 2,
    base_price: 8000
  }
}

COLORS = [
  'White', 'Black', 'Silver', 'Blue', 'Red', 'Gray',
  'Green', 'Orange', 'Yellow', 'Purple', 'Brown', 'Beige'
].freeze

STATUSES = [ 'active', 'inactive', 'maintenance' ].freeze

FUEL_CONSUMPTION = {
  car: { gasoline: 7.5, diesel: 6.5, hybrid: 5.0, electric: 0.0 },
  truck: { diesel: 25.0, lng: 22.0 },
  van: { diesel: 9.5, electric: 0.0, lpg: 10.0 },
  motorcycle: { gasoline: 3.5, hybrid: 3.0 }
}.freeze

MAINTENANCE_TYPES = [
  'Oil Change', 'Brake Inspection', 'Tire Rotation',
  'Air Filter Replacement', 'Transmission Service',
  'Coolant Flush', 'Battery Check', 'Suspension Check'
].freeze

# ============================================
# HELPER PARA GENERAR DATOS REALISTAS
# ============================================

def random_license_plate
  region_code = %w[B M V A Z C].sample # Código de provincia ES
  numbers = rand(1000..9999)
  letters = ('A'..'Z').to_a.sample(3).join
  "#{numbers}#{region_code}#{letters}"
end

def random_vin
  "ES#{('0'..'9').to_a.sample(8).join}#{('A'..'Z').to_a.sample(3).join}"
end

# ============================================
# GENERACIÓN DE VEHÍCULOS POR TENANT
# ============================================

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
      10  # Flota pequeña pero variada
    when 'global-logistics'
      40  # Flota mediana
    when 'enterprise-mega'
      80  # Flota grande con variedad
    else
      15
    end

    # ESTADÍSTICAS PARA TRACKING
    vehicles_created = 0
    vehicles_by_type = {}
    maintenance_scheduled = 0

    vehicle_count.times do |i|
      # Determinar tipo de vehículo (con pesos probabilísticos)
      case tenant.slug
      when 'tech-startup'
        vehicle_type = [ :car, :van ].sample
      when 'global-logistics'
        weights = { truck: 0.4, van: 0.4, car: 0.15, motorcycle: 0.05 }
        vehicle_type = weights.max_by { |_k, w| rand ** (1.0 / w) }[0]
      when 'enterprise-mega'
        weights = { truck: 0.35, van: 0.35, car: 0.25, motorcycle: 0.05 }
        vehicle_type = weights.max_by { |_k, w| rand ** (1.0 / w) }[0]
      end

      vehicles_by_type[vehicle_type] = (vehicles_by_type[vehicle_type] || 0) + 1

      # Datos específicos del vehículo
      vehicle_info = VEHICLE_CATALOG[vehicle_type]
      make = vehicle_info[:makes].keys.sample
      model = vehicle_info[:makes][make].sample
      fuel_type = vehicle_info[:fuel_types].sample
      color = COLORS.sample
      status = STATUSES.sample
      year = rand(2016..2024)
      month = rand(1..12)
      day = rand(1..28)

      # Datos realistas
      purchase_date = Date.new(year, month, day)
      registration_date = purchase_date + rand(1..30).days

      # Calculatekilometraje realista
      months_in_service = ((Date.current - purchase_date).to_i / 30.0).round
      annual_km = case vehicle_type
      when :truck then rand(80000..120000)
      when :van then rand(50000..80000)
      when :car then rand(30000..60000)
      when :motorcycle then rand(8000..15000)
      end

      odometer = (months_in_service * annual_km / 12.0).to_i + rand(0..5000)

      license_plate = random_license_plate
      fleet_number = "#{tenant.slug[0..2].upcase}-#{vehicle_type.to_s[0..1].upcase}#{(i + 1).to_s.rjust(4, '0')}"

      # Datos de expiración
      registration_expiry = registration_date + 4.years
      insurance_expiry = Date.current + rand(30..360).days

      # Algunos registros próximos a expirar
      if i % 12 == 0
        registration_expiry = 20.days.from_now
      end
      if i % 15 == 0
        insurance_expiry = 10.days.from_now
      end

      # Última revisión
      last_maintenance_days = case status
      when 'maintenance'
        rand(8..12).months.ago
      when 'active'
        rand(1..6).months.ago
      else
        rand(6..24).months.ago
      end

      # Nodo de asignación
      node = nodes_with_vehicles.sample

      # Crear vehículo
      vehicle = Vehicle.create_with(
        name: "#{make} #{model} (#{license_plate})",
        vehicle_type: vehicle_type.to_s,
        make: make,
        model: model,
        year: year,
        color: color,
        license_plate: license_plate,
        vin: random_vin,
        fleet_number: fleet_number,
        status: status,
        fuel_type: fuel_type,
        fuel_capacity: case vehicle_type
                       when :truck then rand(250..400)
                       when :van then rand(60..100)
                       when :car then rand(45..70)
                       when :motorcycle then rand(12..20)
                       end,
        passenger_capacity: vehicle_info[:passenger_capacity],
        odometer: odometer,
        purchase_date: purchase_date,
        registration_expires_at: registration_expiry,
        insurance_expires_at: insurance_expiry,
        last_maintenance_date: last_maintenance_days,
        organizational_node: node,
        metadata: {
          gps_enabled: [ true, false ].sample,
          telematics_unit: [ 'TUnit-GPS-01', 'TUnit-GPS-02', 'TUnit-GPS-03', nil ].sample,
          tags: [ 'priority', 'long-distance', 'urban', 'backup', 'high-value' ].sample(rand(0..2)),
          acquisition_date: purchase_date.to_s,
          depreciation_rate: 0.15
        },
        specifications: {
          engine_cc: case vehicle_type
                     when :motorcycle then rand(250..1200)
                     when :car then rand(1200..2000)
                     when :van then rand(2000..3000)
                     when :truck then rand(10000..16000)
                     end,
          power_hp: case vehicle_type
                    when :motorcycle then rand(25..150)
                    when :car then rand(90..200)
                    when :van then rand(140..250)
                    when :truck then rand(300..500)
                    end,
          transmission: [ 'Manual', 'Automatic', 'CVT' ].sample,
          axles: vehicle_type == :truck ? rand(2..3) : 2,
          doors: vehicle_type == :truck ? 2 : (vehicle_type == :motorcycle ? 0 : rand(2..5)),
          load_capacity_kg: case vehicle_type
                            when :truck then rand(18000..26000)
                            when :van then rand(1000..3500)
                            else nil
                            end,
          max_speed_kmh: case vehicle_type
                         when :motorcycle then rand(180..280)
                         when :car then rand(180..250)
                         when :van then rand(160..200)
                         when :truck then rand(90..120)
                         end,
          fuel_consumption_l100km: FUEL_CONSUMPTION[vehicle_type][fuel_type] || 0
        }
      ).find_or_create_by!(
        tenant: tenant,
        license_plate: license_plate
      )

      vehicles_created += 1
    end

    # ESTADÍSTICAS DEL TENANT
    puts "    ✓ Created #{vehicles_created} vehicles"
    puts "      Vehicle types: #{vehicles_by_type.map { |k, v| "#{k}: #{v}" }.join(', ')}"

    # Contar por estado
    by_status = Vehicle.group(:status).count
    puts "      Status: #{by_status.map { |k, v| "#{k}: #{v}" }.join(', ')}"

    # Vehículos con mantenimiento próximo
    needs_maintenance = Vehicle.where('last_maintenance_date < ?', 6.months.ago).count
    puts "      Need maintenance: #{needs_maintenance}"

    # Registros expirando
    expiring_registration = Vehicle.where('registration_expires_at BETWEEN ? AND ?',
                                         Date.current, 30.days.from_now).count
    expiring_insurance = Vehicle.where('insurance_expires_at BETWEEN ? AND ?',
                                       Date.current, 30.days.from_now).count
    puts "      Expiring soon: #{expiring_registration} registrations, #{expiring_insurance} insurance"
    puts "      Maintenance records created: #{maintenance_scheduled}"
  end
end

# ============================================
# RESUMEN GLOBAL
# ============================================

puts "\n  📊 Global Vehicles Summary:"

ActsAsTenant.without_tenant do
  total_vehicles = Vehicle.unscoped.count

  puts "    - Total Vehicles: #{total_vehicles}"
  puts "    - Total Maintenance Records: #{total_maintenance}"

  puts "\n    - Vehicle Distribution by Type:"
  Vehicle.unscoped.group(:vehicle_type).count.each do |type, count|
    percentage = ((count.to_f / total_vehicles) * 100).round(1)
    puts "      - #{type.to_s.capitalize}: #{count} (#{percentage}%)"
  end

  puts "\n    - Status Distribution:"
  Vehicle.unscoped.group(:status).count.each do |status, count|
    percentage = ((count.to_f / total_vehicles) * 100).round(1)
    puts "      - #{status.capitalize}: #{count} (#{percentage}%)"
  end

  puts "\n    - Fuel Type Distribution:"
  Vehicle.unscoped.group(:fuel_type).count.each do |fuel, count|
    percentage = ((count.to_f / total_vehicles) * 100).round(1)
    puts "      - #{fuel.capitalize}: #{count} (#{percentage}%)"
  end

  puts "\n    - Fleet Age Analysis:"
  avg_year = Vehicle.unscoped.average(:year).round
  oldest = Vehicle.unscoped.minimum(:year)
  newest = Vehicle.unscoped.maximum(:year)
  puts "      - Average year: #{avg_year}"
  puts "      - Range: #{oldest} - #{newest}"

  puts "\n    - Mileage Summary:"
  avg_odometer = Vehicle.unscoped.average(:odometer).round
  max_odometer = Vehicle.unscoped.maximum(:odometer)
  min_odometer = Vehicle.unscoped.minimum(:odometer)
  puts "      - Average: #{avg_odometer} km"
  puts "      - Range: #{min_odometer} - #{max_odometer} km"

  puts "\n    - Maintenance Status:"
  needs_service = Vehicle.unscoped.where('last_maintenance_date < ?', 6.months.ago).count
  puts "      - Needs service (>6 months): #{needs_service}"

  expiring_reg = Vehicle.unscoped.where('registration_expires_at BETWEEN ? AND ?',
                                        Date.current, 30.days.from_now).count
  expiring_ins = Vehicle.unscoped.where('insurance_expires_at BETWEEN ? AND ?',
                                        Date.current, 30.days.from_now).count
  puts "      - Registration expiring (30 days): #{expiring_reg}"
  puts "      - Insurance expiring (30 days): #{expiring_ins}"
end

puts "\n  🚗 Sample Vehicles by Tenant:"

[
  Tenant.find_by(slug: 'tech-startup'),
  Tenant.find_by(slug: 'global-logistics'),
  Tenant.find_by(slug: 'enterprise-mega')
].compact.each do |tenant|
  ActsAsTenant.with_tenant(tenant) do
    puts "\n    #{tenant.name}:"
    Vehicle.limit(3).each do |v|
      puts "      • #{v.fleet_number}: #{v.name}"
      puts "        - Type: #{v.vehicle_type}, Year: #{v.year}, Fuel: #{v.fuel_type}"
      puts "        - Status: #{v.status}, Odometer: #{v.odometer} km"
      puts "        - Location: #{v.organizational_node.name if v.organizational_node}"
    end
  end
end

puts "\n  ✅ Vehicle seeding completed successfully!"
