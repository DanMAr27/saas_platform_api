# frozen_string_literal: true

# db/seeds/05_organizational_structure.rb
# Estructura organizacional jerárquica para tenants

puts "\n🌳 Creating Organizational Structure..."

# Solo crear estructura para tenants activos
active_tenants = [
  Tenant.find_by(slug: 'tech-startup'),
  Tenant.find_by(slug: 'global-logistics'),
  Tenant.find_by(slug: 'enterprise-mega')
].compact

active_tenants.each do |tenant|
  puts "\n  Creating structure for: #{tenant.name}"

  ActsAsTenant.with_tenant(tenant) do
    # ============================================
    # NIVELES ORGANIZACIONALES
    # ============================================

    company_level = OrganizationalNodeLevel.create_with(
      name: 'Company',
      description: 'Top level organizational unit',
      level_order: 1,
      allows_vehicles: false,
      allows_users: true,
      is_system: true
    ).find_or_create_by!(tenant: tenant, slug: 'company')

    region_level = OrganizationalNodeLevel.create_with(
      name: 'Region',
      description: 'Geographic regions',
      level_order: 2,
      allows_vehicles: false,
      allows_users: true,
      is_system: true
    ).find_or_create_by!(tenant: tenant, slug: 'region')

    branch_level = OrganizationalNodeLevel.create_with(
      name: 'Branch',
      description: 'Physical locations or branches',
      level_order: 3,
      allows_vehicles: true,
      allows_users: true,
      is_system: true
    ).find_or_create_by!(tenant: tenant, slug: 'branch')

    department_level = OrganizationalNodeLevel.create_with(
      name: 'Department',
      description: 'Departments within branches',
      level_order: 4,
      allows_vehicles: false,
      allows_users: true,
      is_system: true
    ).find_or_create_by!(tenant: tenant, slug: 'department')

    puts "    ✓ Created 4 organizational levels"

    # ============================================
    # NODOS - DEPENDE DEL TENANT
    # ============================================

    case tenant.slug
    when 'tech-startup'
      # Estructura simple para startup
      company = OrganizationalNode.create_with(
        level: company_level,
        name: "#{tenant.name} HQ",
        code: 'HQ',
        status: 'active',
        city: tenant.city,
        country: tenant.country
      ).find_or_create_by!(tenant: tenant, parent: nil)

      barcelona = OrganizationalNode.create_with(
        level: branch_level,
        name: 'Barcelona Office',
        code: 'BCN',
        status: 'active',
        address: tenant.address,
        city: 'Barcelona',
        country: 'ES'
      ).find_or_create_by!(tenant: tenant, parent: company)

      puts "    ✓ Created 2 nodes (simple structure)"

    when 'global-logistics'
      # Estructura compleja para logistics
      company = OrganizationalNode.create_with(
        level: company_level,
        name: "#{tenant.name} Central",
        code: 'CENTRAL',
        status: 'active'
      ).find_or_create_by!(tenant: tenant, parent: nil)

      # Regiones
      north = OrganizationalNode.create_with(
        level: region_level,
        name: 'Northern Region',
        code: 'REGION-N',
        status: 'active'
      ).find_or_create_by!(tenant: tenant, parent: company)

      south = OrganizationalNode.create_with(
        level: region_level,
        name: 'Southern Region',
        code: 'REGION-S',
        status: 'active'
      ).find_or_create_by!(tenant: tenant, parent: company)

      east = OrganizationalNode.create_with(
        level: region_level,
        name: 'Eastern Region',
        code: 'REGION-E',
        status: 'active'
      ).find_or_create_by!(tenant: tenant, parent: company)

      # Sucursales Norte
      bcn = OrganizationalNode.create_with(
        level: branch_level,
        name: 'Barcelona Hub',
        code: 'BCN-01',
        status: 'active',
        city: 'Barcelona',
        country: 'ES'
      ).find_or_create_by!(tenant: tenant, parent: north)

      girona = OrganizationalNode.create_with(
        level: branch_level,
        name: 'Girona Branch',
        code: 'GRO-01',
        status: 'active',
        city: 'Girona',
        country: 'ES'
      ).find_or_create_by!(tenant: tenant, parent: north)

      # Sucursales Sur
      valencia = OrganizationalNode.create_with(
        level: branch_level,
        name: 'Valencia Hub',
        code: 'VLC-01',
        status: 'active',
        city: 'Valencia',
        country: 'ES'
      ).find_or_create_by!(tenant: tenant, parent: south)

      alicante = OrganizationalNode.create_with(
        level: branch_level,
        name: 'Alicante Branch',
        code: 'ALC-01',
        status: 'active',
        city: 'Alicante',
        country: 'ES'
      ).find_or_create_by!(tenant: tenant, parent: south)

      # Sucursales Este
      tarragona = OrganizationalNode.create_with(
        level: branch_level,
        name: 'Tarragona Branch',
        code: 'TGN-01',
        status: 'active',
        city: 'Tarragona',
        country: 'ES'
      ).find_or_create_by!(tenant: tenant, parent: east)

      # Departamentos en Barcelona
      sales = OrganizationalNode.create_with(
        level: department_level,
        name: 'Sales Department',
        code: 'BCN-SALES',
        status: 'active'
      ).find_or_create_by!(tenant: tenant, parent: bcn)

      logistics_dept = OrganizationalNode.create_with(
        level: department_level,
        name: 'Logistics Department',
        code: 'BCN-LOG',
        status: 'active'
      ).find_or_create_by!(tenant: tenant, parent: bcn)

      support = OrganizationalNode.create_with(
        level: department_level,
        name: 'Customer Support',
        code: 'BCN-SUP',
        status: 'active'
      ).find_or_create_by!(tenant: tenant, parent: bcn)

      puts "    ✓ Created 13 nodes (complex hierarchy)"

    when 'enterprise-mega'
      # Estructura enterprise muy completa
      company = OrganizationalNode.create_with(
        level: company_level,
        name: "#{tenant.name}",
        code: 'CORP',
        status: 'active'
      ).find_or_create_by!(tenant: tenant, parent: nil)

      # 4 Regiones
      [ 'North', 'South', 'East', 'West' ].each_with_index do |region_name, idx|
        region = OrganizationalNode.create_with(
          level: region_level,
          name: "#{region_name} Region",
          code: "REG-#{region_name[0]}",
          status: 'active'
        ).find_or_create_by!(tenant: tenant, parent: company)

        # 2 sucursales por región
        2.times do |branch_idx|
          OrganizationalNode.create_with(
            level: branch_level,
            name: "#{region_name} Branch #{branch_idx + 1}",
            code: "#{region_name[0]}-BR#{branch_idx + 1}",
            status: 'active',
            country: 'ES'
          ).find_or_create_by!(tenant: tenant, parent: region)
        end
      end

      puts "    ✓ Created 13 nodes (enterprise structure)"
    end

    # Verificar closure table
    node_count = OrganizationalNode.where(tenant: tenant).count
    closure_count = OrganizationalNodeClosure.joins(:ancestor)
      .where(organizational_nodes: { tenant_id: tenant.id }).count

    puts "    ✓ Closure table: #{closure_count} records for #{node_count} nodes"
  end
end

# ============================================
# RESUMEN
# ============================================

puts "\n  📊 Organizational Structure Summary:"

# CORRECCIÓN: Usar without_tenant para queries globales
ActsAsTenant.without_tenant do
  total_levels = OrganizationalNodeLevel.unscoped.count
  total_nodes = OrganizationalNode.unscoped.count
  total_closures = OrganizationalNodeClosure.unscoped.count

  puts "    - Total Levels: #{total_levels}"
  puts "    - Total Nodes: #{total_nodes}"
  puts "    - Total Closures: #{total_closures}"

  # Distribución de nodos por nivel
  puts "\n    - Nodes by Level:"
  OrganizationalNode.unscoped
    .joins(:level)
    .select('organizational_node_levels.name, organizational_node_levels.level_order, COUNT(*) as node_count')
    .group('organizational_node_levels.name', 'organizational_node_levels.level_order')
    .order('organizational_node_levels.level_order')
    .each do |result|
      puts "      - #{result.name}: #{result.node_count}"
    end
end

puts "\n  🏢 Structure by Tenant:"
active_tenants.each do |tenant|
  ActsAsTenant.with_tenant(tenant) do
    node_count = OrganizationalNode.count
    root_count = OrganizationalNode.roots.count

    # Calcular profundidad máxima
    max_depth = OrganizationalNodeClosure.maximum(:depth) || 0

    puts "    #{tenant.name}:"
    puts "      - Nodes: #{node_count}"
    puts "      - Roots: #{root_count}"
    puts "      - Max Depth: #{max_depth}"

    # Mostrar jerarquía simple
    OrganizationalNode.roots.first(2).each do |root|
      puts "      - #{root.name}"
      root.children.limit(3).each do |child|
        puts "        └─ #{child.name}"
      end
    end
  end
end

puts "\n  ✅ Organizational structure created successfully!"
