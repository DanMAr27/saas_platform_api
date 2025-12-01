# db/seeds.rb
# Sistema de seeds completo para desarrollo y testing

puts "🌱 Starting database seeding..."
puts "=" * 80

# ============================================
# CONFIGURACIÓN
# ============================================

# Deshabilitar auditoría durante seeds
PaperTrail.enabled = false

# Deshabilitar validaciones de tenant temporalmente
ActsAsTenant.current_tenant = nil

# ============================================
# OPCIÓN: LIMPIAR BASE DE DATOS
# ============================================

if ENV['RESET_DB'] == 'true' || Rails.env.development?
  puts "\n⚠️  RESET_DB enabled - Cleaning database..."

  # Orden de eliminación (respetando foreign keys)
  [
    'organizational_node_closures',
    'user_vehicle_scopes',
    'user_node_scopes',
    'vehicles',
    'organizational_nodes',
    'organizational_node_levels',
    'tenant_memberships',
    'platform_memberships',
    'jwt_blacklists',
    'tenants',
    'users',
    'roles',
    'versions' # PaperTrail
  ].each do |table|
    begin
      ActiveRecord::Base.connection.execute("TRUNCATE TABLE #{table} RESTART IDENTITY CASCADE")
      puts "  ✓ Truncated: #{table}"
    rescue => e
      puts "  ⚠️  Could not truncate #{table}: #{e.message}"
    end
  end

  puts "\n✅ Database cleaned!\n"
end

# ============================================
# CARGAR SEEDS EN ORDEN
# ============================================

seeds_dir = Rails.root.join('db', 'seeds')

# Orden específico de ejecución
seed_files = [
  '01_roles.rb',           # Primero: catálogo de roles
  '02_users.rb',           # Segundo: usuarios base
  '03_platform_admins.rb', # Tercero: admins de plataforma
  '04_tenants.rb',         # Cuarto: tenants y membresías
  '05_organizational_structure.rb', # Quinto: estructura organizacional
  '06_vehicles.rb',        # Sexto: vehículos
  '07_scopes.rb'           # Séptimo: scopes de acceso
]

seed_files.each do |file|
  file_path = seeds_dir.join(file)

  if File.exist?(file_path)
    puts "\n" + "=" * 80
    puts "📄 Processing: #{file}"
    puts "=" * 80

    begin
      load(file_path)
    rescue => e
      puts "\n❌ Error in #{file}:"
      puts "   #{e.message}"
      puts "   #{e.backtrace.first(3).join("\n   ")}"
      raise e if Rails.env.production?
    end
  else
    puts "\n⚠️  File not found: #{file}"
  end
end

# ============================================
# RESUMEN FINAL
# ============================================

puts "\n" + "=" * 80
puts "📊 FINAL DATABASE SUMMARY"
puts "=" * 80

puts "\n👥 Users & Authentication:"
puts "  - Total Users: #{User.count}"
puts "  - Verified Users: #{User.verified.count}"
puts "  - Active Users: #{User.kept.count}"
puts "  - Deleted Users: #{User.discarded.count}"

puts "\n🎭 Roles & Memberships:"
puts "  - Roles: #{Role.count}"
puts "    - Platform Roles: #{Role.platform_roles.count}"
puts "    - Tenant Roles: #{Role.tenant_roles.count}"
puts "  - Platform Memberships: #{PlatformMembership.count}"
puts "  - Tenant Memberships: #{TenantMembership.count}"

puts "\n🏢 Tenants:"
puts "  - Total Tenants: #{Tenant.count}"
puts "    - Trial: #{Tenant.trial.count}"
puts "    - Active: #{Tenant.active.count}"
puts "    - Suspended: #{Tenant.suspended.count}"

if defined?(OrganizationalNode)
  # Temporalmente desactivar ActsAsTenant para contar
  ActsAsTenant.without_tenant do
    puts "\n🌳 Organizational Structure:"
    puts "  - Levels: #{OrganizationalNodeLevel.unscoped.count}"
    puts "  - Nodes: #{OrganizationalNode.unscoped.count}"
    puts "  - Closure Records: #{OrganizationalNodeClosure.count}"
  end
end

if defined?(Vehicle)
  # Temporalmente desactivar ActsAsTenant para contar
  ActsAsTenant.without_tenant do
    puts "\n🚗 Vehicles:"
    puts "  - Total Vehicles: #{Vehicle.unscoped.count}"

    # Contar por estado requiere unscoped
    vehicles_by_status = Vehicle.unscoped.group(:status).count
    puts "  - Active: #{vehicles_by_status['active'] || 0}"
    puts "  - In Maintenance: #{vehicles_by_status['maintenance'] || 0}"
    puts "  - Inactive: #{vehicles_by_status['inactive'] || 0}"
  end
end

puts "\n" + "=" * 80
puts "✅ Database seeding completed successfully! 🎉"
puts "=" * 80

# Re-habilitar auditoría
PaperTrail.enabled = true

puts "\n💡 Useful commands:"
puts "  - Reset & reseed: rails db:reset RESET_DB=true"
puts "  - Just reseed: rails db:seed RESET_DB=true"
puts ""
