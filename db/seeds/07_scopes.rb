# frozen_string_literal: true

# db/seeds/07_scopes.rb
# User scopes para nodos y vehículos

puts "\n🔐 Creating Access Scopes..."

# ============================================
# GLOBAL LOGISTICS - SCOPES COMPLETOS
# ============================================

logistics = Tenant.find_by(slug: 'global-logistics')

if logistics
  puts "\n  Creating scopes for: #{logistics.name}"

  ActsAsTenant.with_tenant(logistics) do
    # Obtener usuarios y recursos
    managers = TenantMembership.where(tenant: logistics)
                               .managers.active
                               .includes(:user).map(&:user)

    drivers = TenantMembership.where(tenant: logistics)
                              .drivers.active
                              .includes(:user).map(&:user)

    nodes = OrganizationalNode.where(tenant: logistics).to_a
    vehicles = Vehicle.where(tenant: logistics).active.to_a

    # ============================================
    # NODE SCOPES PARA MANAGERS
    # ============================================

    puts "\n    Node Scopes for Managers:"

    managers.each_with_index do |manager, idx|
      # Cada manager gestiona 1-2 regiones/ramas
      assigned_nodes = nodes.sample(rand(1..3))

      assigned_nodes.each do |node|
        UserNodeScope.create_with(
          access_type: 'write',
          include_children: true,
          organizational_node: node,
          tenant: logistics
        ).find_or_create_by!(
          user: manager
        )
      end

      puts "      ✓ Manager #{idx + 1}: #{assigned_nodes.count} nodes (write + children)"
    end

    # ============================================
    # VEHICLE SCOPES PARA DRIVERS
    # ============================================

    puts "\n    Vehicle Scopes for Drivers:"

    drivers.each_with_index do |driver, idx|
      # Cada driver tiene acceso a 1-3 vehículos
      assigned_vehicles = vehicles.sample(rand(1..3))

      assigned_vehicles.each do |vehicle|
        UserVehicleScope.create_with(
          access_type: 'drive',
          valid_from: 1.month.ago,
          valid_until: 6.months.from_now,
          vehicle: vehicle,
          tenant: logistics
        ).find_or_create_by!(
          user: driver
        )
      end

      puts "      ✓ Driver #{idx + 1}: #{assigned_vehicles.count} vehicles (drive access)"
    end

    # ============================================
    # SCOPES TEMPORALES (ALGUNOS DRIVERS)
    # ============================================

    puts "\n    Temporary Vehicle Access:"

    temp_drivers = drivers.sample(2)
    temp_drivers.each_with_index do |driver, idx|
      vehicle = vehicles.sample

      UserVehicleScope.create_with(
        access_type: 'drive',
        valid_from: Time.current,
        valid_until: 2.weeks.from_now,
        vehicle: vehicle,
        tenant: logistics
      ).find_or_create_by!(
        user: driver,
        vehicle: vehicle
      )

      puts "      ✓ Temporary access: Driver -> #{vehicle.fleet_number} (2 weeks)"
    end

    # ============================================
    # SCOPES EXPIRADOS (PARA TESTING)
    # ============================================

    if drivers.any?
      expired_driver = drivers.first
      expired_vehicle = vehicles.first

      UserVehicleScope.create!(
        user: expired_driver,
        vehicle: expired_vehicle,
        tenant: logistics,
        access_type: 'drive',
        valid_from: 3.months.ago,
        valid_until: 1.week.ago
      )

      puts "      ✓ Expired access created (for testing)"
    end

    # Estadísticas
    puts "\n    Statistics:"
    puts "      - Node Scopes: #{UserNodeScope.count}"
    puts "      - Vehicle Scopes: #{UserVehicleScope.count}"
    puts "      - Active Vehicle Scopes: #{UserVehicleScope.active.count}"
    puts "      - Expired Vehicle Scopes: #{UserVehicleScope.expired.count}"
  end
end

# ============================================
# TECH STARTUP - SCOPES SIMPLES
# ============================================

techstart = Tenant.find_by(slug: 'tech-startup')

if techstart
  puts "\n  Creating scopes for: #{techstart.name}"

  ActsAsTenant.with_tenant(techstart) do
    managers = TenantMembership.where(tenant: techstart)
                               .managers.active
                               .includes(:user).map(&:user)

    vehicles = Vehicle.where(tenant: techstart).to_a

    # Manager tiene acceso a todos los vehículos
    if managers.any? && vehicles.any?
      manager = managers.first

      vehicles.each do |vehicle|
        UserVehicleScope.create_with(
          access_type: 'write',
          tenant: techstart
        ).find_or_create_by!(
          user: manager,
          vehicle: vehicle
        )
      end

      puts "    ✓ Manager: Full access to #{vehicles.count} vehicles"
    end
  end
end

# ============================================
# ENTERPRISE - SCOPES COMPLEJOS
# ============================================

enterprise = Tenant.find_by(slug: 'enterprise-mega')

if enterprise
  puts "\n  Creating scopes for: #{enterprise.name}"

  ActsAsTenant.with_tenant(enterprise) do
    managers = TenantMembership.where(tenant: enterprise)
                               .managers.active
                               .includes(:user).map(&:user)

    nodes = OrganizationalNode.where(tenant: enterprise).to_a
    regions = nodes.select { |n| n.level.slug == 'region' }

    # Cada manager gestiona una región completa
    managers.each_with_index do |manager, idx|
      next if regions.empty?

      region = regions[idx % regions.size]

      UserNodeScope.create_with(
        access_type: 'admin',
        include_children: true,
        organizational_node: region,
        tenant: enterprise
      ).find_or_create_by!(
        user: manager
      )

      puts "    ✓ Manager #{idx + 1}: Admin access to #{region.name} + children"
    end
  end
end

# ============================================
# RESUMEN FINAL
# ============================================

puts "\n  📊 Access Scopes Summary:"

# Usar unscoped para contar sin filtros
ActsAsTenant.without_tenant do
  puts "    - Total Node Scopes: #{UserNodeScope.unscoped.count}"
  puts "      - Read Access: #{UserNodeScope.unscoped.where(access_type: 'read').count}"
  puts "      - Write Access: #{UserNodeScope.unscoped.where(access_type: 'write').count}"
  puts "      - Admin Access: #{UserNodeScope.unscoped.where(access_type: 'admin').count}"
  puts "      - With Children: #{UserNodeScope.unscoped.where(include_children: true).count}"

  puts "\n    - Total Vehicle Scopes: #{UserVehicleScope.unscoped.count}"
  puts "      - Read Access: #{UserVehicleScope.unscoped.where(access_type: 'read').count}"
  puts "      - Write Access: #{UserVehicleScope.unscoped.where(access_type: 'write').count}"
  puts "      - Drive Access: #{UserVehicleScope.unscoped.where(access_type: 'drive').count}"

  # Active/Expired sin scope
  active_count = UserVehicleScope.unscoped.where(
    "(valid_from IS NULL OR valid_from <= ?) AND (valid_until IS NULL OR valid_until >= ?)",
    Time.current, Time.current
  ).count
  expired_count = UserVehicleScope.unscoped.where("valid_until < ?", Time.current).count

  puts "      - Active: #{active_count}"
  puts "      - Expired: #{expired_count}"
end

puts "\n  🔍 Sample Access Patterns:"

# Mostrar algunos ejemplos de acceso
if logistics
  ActsAsTenant.with_tenant(logistics) do
    sample_manager = TenantMembership.managers.active.first&.user
    sample_driver = TenantMembership.drivers.active.first&.user

    if sample_manager
      node_scopes = UserNodeScope.where(user: sample_manager).count
      puts "    Manager (#{sample_manager.email}):"
      puts "      - Node Scopes: #{node_scopes}"
    end

    if sample_driver
      vehicle_scopes_count = UserVehicleScope.where(user: sample_driver)
        .where("(valid_from IS NULL OR valid_from <= ?) AND (valid_until IS NULL OR valid_until >= ?)",
               Time.current, Time.current).count
      puts "    Driver (#{sample_driver.email}):"
      puts "      - Active Vehicle Access: #{vehicle_scopes_count}"
    end
  end
end
