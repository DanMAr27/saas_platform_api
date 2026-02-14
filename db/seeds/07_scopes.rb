# db/seeds/07_scopes.rb
# Crear scopes de acceso y activar membresías pendientes

puts "\n🔐 Creating Access Scopes..."

# Tenants activos con estructura organizacional
active_tenants = [
  Tenant.find_by(slug: 'acme-corp'),
  Tenant.find_by(slug: 'tech-startup'),
  Tenant.find_by(slug: 'global-logistics'),
  Tenant.find_by(slug: 'enterprise-mega')
].compact

# Roles
manager_role = Role.find_by!(slug: 'tenant_manager')
driver_role = Role.find_by!(slug: 'tenant_driver')
viewer_role = Role.find_by(slug: 'tenant_viewer')
coordinator_role = Role.find_by(slug: 'fleet_coordinator')

# ============================================
# HELPERS
# ============================================

# helpers
def assign_node_scope(user, node, tenant, role: nil, access_type: 'write', include_children: true)
  # Si no se pasa rol, intentar inferirlo (solo si el usuario tiene un único rol compatible)
  unless role
    role = user.tenant_memberships.find_by(tenant: tenant)&.role
  end

  UserNodeScope.create_with(
    access_type: access_type,
    include_children: include_children,
    created_by: tenant.primary_admin&.id
  ).find_or_create_by!(
    user: user,
    organizational_node: node,
    tenant: tenant,
    role: role
  )
end

def assign_vehicle_scope(user, vehicle, tenant, role: nil, access_type: 'drive', valid_from: nil, valid_until: nil)
  # Si no se pasa rol, intentar inferirlo
  unless role
    role = user.tenant_memberships.find_by(tenant: tenant)&.role
  end

  UserVehicleScope.create_with(
    access_type: access_type,
    valid_from: valid_from || Time.current,
    valid_until: valid_until,
    created_by: tenant.primary_admin&.id
  ).find_or_create_by!(
    user: user,
    vehicle: vehicle,
    tenant: tenant,
    role: role
  )
end

def activate_membership(membership)
  return unless membership.invited?

  # Verificar que tenga los scopes necesarios
  if membership.has_valid_scopes?
    membership.update!(status: 'active')
    puts "      ✓ Activated: #{membership.user.email} as #{membership.role.name}"
    true
  else
    puts "      ⚠️  Cannot activate #{membership.user.email}: missing scopes"
    false
  end
end

# ============================================
# PROCESAR CADA TENANT
# ============================================

stats = {
  node_scopes: 0,
  vehicle_scopes: 0,
  activated_memberships: 0
}

active_tenants.each do |tenant|
  puts "\n  Processing: #{tenant.name}"

  ActsAsTenant.with_tenant(tenant) do
    # ============================================
    # OBTENER DATOS DEL TENANT
    # ============================================

    nodes = OrganizationalNode.active.includes(:level).to_a
    vehicles = Vehicle.active.to_a

    if nodes.empty?
      puts "    ⚠️  No organizational nodes found - skipping node scopes"
    end

    if vehicles.empty?
      puts "    ⚠️  No vehicles found - skipping vehicle scopes"
    end

    # ============================================
    # MANAGERS: Asignar NODE SCOPES
    # ============================================

    manager_memberships = TenantMembership
      .where(tenant: tenant, role: manager_role, status: 'invited')
      .includes(:user)

    if manager_memberships.any? && nodes.any?
      puts "\n    Assigning Node Scopes to Managers:"

      manager_memberships.each_with_index do |membership, idx|
        # Asignar nodos de forma distribuida
        case tenant.slug
        when 'acme-corp', 'tech-startup'
          # Tenants pequeños: acceso a todos los nodos
          nodes.each do |node|
            assign_node_scope(
              membership.user, node, tenant,
              role: membership.role,
              access_type: 'write',
              include_children: true
            )
            stats[:node_scopes] += 1
          end

        when 'global-logistics', 'enterprise-mega'
          # Tenants grandes: asignar por región/área
          # Distribuir managers entre regiones
          regions = nodes.select { |n| n.level.slug == 'region' }

          if regions.any?
            # Asignar una región específica a cada manager
            assigned_region = regions[idx % regions.size]
            assign_node_scope(
              membership.user, assigned_region, tenant,
              role: membership.role,
              access_type: 'write',
              include_children: true # Incluye branches y departamentos
            )
            stats[:node_scopes] += 1

            puts "      - #{membership.user.email}: #{assigned_region.name} (with children)"
          else
            # Si no hay regiones, asignar branches
            branches = nodes.select { |n| n.level.slug == 'branch' }
            assigned_branches = branches.sample(rand(1..3))

            assigned_branches.each do |branch|
              assign_node_scope(
              membership.user, branch, tenant,
              role: membership.role,
              access_type: 'write',
              include_children: true
            )
              stats[:node_scopes] += 1
            end

            puts "      - #{membership.user.email}: #{assigned_branches.size} branches"
          end
        end

        # Activar la membresía
        if activate_membership(membership)
          stats[:activated_memberships] += 1
        end
      end
    end

    # ============================================
    # FLEET COORDINATORS: Asignar NODE SCOPES
    # ============================================

    if coordinator_role
      coordinator_memberships = TenantMembership
        .where(tenant: tenant, role: coordinator_role, status: 'invited')
        .includes(:user)

      if coordinator_memberships.any? && nodes.any?
        puts "\n    Assigning Node Scopes to Fleet Coordinators:"

        coordinator_memberships.each do |membership|
          # Coordinadores tienen acceso a múltiples branches
          branches = nodes.select { |n| n.level.slug == 'branch' }
          assigned_branches = branches.sample(rand(2..5).clamp(1, branches.size))

          assigned_branches.each do |branch|
            assign_node_scope(
              membership.user, branch, tenant,
              role: membership.role,
              access_type: 'write',
              include_children: true
            )
            stats[:node_scopes] += 1
          end

          puts "      - #{membership.user.email}: #{assigned_branches.size} branches"

          if activate_membership(membership)
            stats[:activated_memberships] += 1
          end
        end
      end
    end

    # ============================================
    # VIEWERS: Asignar NODE SCOPES (READ-ONLY)
    # ============================================

    if viewer_role
      viewer_memberships = TenantMembership
        .where(tenant: tenant, role: viewer_role, status: 'invited')
        .includes(:user)

      if viewer_memberships.any? && nodes.any?
        puts "\n    Assigning Node Scopes to Viewers:"

        viewer_memberships.each do |membership|
          # Viewers: acceso read-only a nivel company o región
          top_nodes = nodes.select { |n| n.level.slug.in?(%w[company region]) }

          if top_nodes.any?
            top_node = top_nodes.first
            assign_node_scope(
              membership.user, top_node, tenant,
              role: membership.role,
              access_type: 'read',
              include_children: true # Ver todo debajo
            )
            stats[:node_scopes] += 1

            puts "      - #{membership.user.email}: #{top_node.name} (read-only, with children)"

            if activate_membership(membership)
              stats[:activated_memberships] += 1
            end
          end
        end
      end
    end

    # ============================================
    # DRIVERS: Asignar VEHICLE SCOPES
    # ============================================

    driver_memberships = TenantMembership
      .where(tenant: tenant, role: driver_role, status: 'invited')
      .includes(:user)

    if driver_memberships.any? && vehicles.any?
      puts "\n    Assigning Vehicle Scopes to Drivers:"

      driver_memberships.each_with_index do |membership, idx|
        # Distribuir vehículos entre drivers
        case tenant.slug
        when 'acme-corp', 'tech-startup'
          # Tenants pequeños: 2-3 vehículos por driver
          vehicles_per_driver = rand(2..3).clamp(1, vehicles.size)

        when 'global-logistics'
          # Tenant mediano: 3-5 vehículos por driver
          vehicles_per_driver = rand(3..5).clamp(1, vehicles.size)

        when 'enterprise-mega'
          # Tenant grande: 2-4 vehículos por driver
          vehicles_per_driver = rand(2..4).clamp(1, vehicles.size)
        else
          vehicles_per_driver = 2
        end

        # Asignar vehículos
        start_idx = (idx * vehicles_per_driver) % vehicles.size
        assigned_vehicles = vehicles.rotate(start_idx).take(vehicles_per_driver)

        assigned_vehicles.each do |vehicle|
          # Algunos scopes temporales, otros permanentes
          if rand < 0.3 # 30% con fecha de expiración
            valid_until = rand(30..180).days.from_now
          else
            valid_until = nil # Sin expiración
          end

          assign_vehicle_scope(
            membership.user, vehicle, tenant,
            role: membership.role,
            access_type: 'drive',
            valid_until: valid_until
          )
          stats[:vehicle_scopes] += 1
        end

        expiry_text = assigned_vehicles.any? { |v|
          UserVehicleScope.find_by(user: membership.user, vehicle: v)&.valid_until.present?
        } ? " (some temporary)" : ""

        puts "      - #{membership.user.email}: #{assigned_vehicles.size} vehicles#{expiry_text}"

        if activate_membership(membership)
          stats[:activated_memberships] += 1
        end
      end
    end

    # ============================================
    # USUARIO MULTI-TENANT
    # ============================================

    multi_user = User.find_by(email: 'operativo.universal@example.com')
    if multi_user
      membership = TenantMembership.find_by(
        user: multi_user,
        tenant: tenant,
        status: 'invited'
      )

      if membership
        case membership.role.slug
        when 'tenant_manager'
          # Asignar un nodo
          if nodes.any?
            node = nodes.sample
            assign_node_scope(multi_user, node, tenant, role: membership.role, include_children: true)
            stats[:node_scopes] += 1

            if activate_membership(membership)
              puts "      ✓ Multi-tenant user: #{multi_user.email} (manager)"
              stats[:activated_memberships] += 1
            end
          end

        when 'tenant_driver'
          # Asignar vehículos
          if vehicles.any?
            vehicles.sample(2).each do |vehicle|
              assign_vehicle_scope(multi_user, vehicle, tenant, role: membership.role)
              stats[:vehicle_scopes] += 1
            end

            if activate_membership(membership)
              puts "      ✓ Multi-tenant user: #{multi_user.email} (driver)"
              stats[:activated_memberships] += 1
            end
          end

        when 'tenant_viewer'
          # Asignar acceso read-only
          if nodes.any?
            top_node = nodes.first
            assign_node_scope(multi_user, top_node, tenant, role: membership.role, access_type: 'read', include_children: true)
            stats[:node_scopes] += 1

            if activate_membership(membership)
              puts "      ✓ Multi-tenant user: #{multi_user.email} (viewer)"
              stats[:activated_memberships] += 1
            end
          end
        end
      end
    end
  end
end

# ============================================
# VERIFICAR MEMBRESÍAS PENDIENTES
# ============================================

puts "\n  🔍 Checking for remaining invited memberships..."

remaining_invited = TenantMembership.invited.includes(:user, :role, :tenant)
if remaining_invited.any?
  puts "    ⚠️  #{remaining_invited.count} memberships still invited (missing scopes):"

  remaining_invited.group_by(&:tenant).each do |tenant, memberships|
    puts "      #{tenant.name}:"
    memberships.each do |m|
      puts "        - #{m.user.email} (#{m.role.name})"

      # Diagnóstico
      if m.role.requires_any_scope?
        if m.role.allows_node_scope?
          node_scopes = m.user.user_node_scopes.kept.where(tenant: tenant).count
          puts "          Missing: node scopes (has: #{node_scopes})"
        end

        if m.role.allows_vehicle_scope?
          vehicle_scopes = m.user.user_vehicle_scopes.kept.active.where(tenant: tenant).count
          puts "          Missing: vehicle scopes (has: #{vehicle_scopes})"
        end
      end
    end
  end
else
  puts "    ✅ All memberships with required scopes have been activated!"
end

# ============================================
# RESUMEN FINAL
# ============================================

puts "\n  📊 Access Scopes Summary:"

ActsAsTenant.without_tenant do
  total_node_scopes = UserNodeScope.unscoped.kept.count
  total_vehicle_scopes = UserVehicleScope.unscoped.kept.count

  puts "    - Total Node Scopes: #{total_node_scopes}"
  puts "      - Read Access: #{UserNodeScope.unscoped.kept.read_access.count}"
  puts "      - Write Access: #{UserNodeScope.unscoped.kept.write_access.count}"
  puts "      - Admin Access: #{UserNodeScope.unscoped.kept.admin_access.count}"
  puts "      - With Children: #{UserNodeScope.unscoped.kept.with_children.count}"

  puts "\n    - Total Vehicle Scopes: #{total_vehicle_scopes}"
  puts "      - Read Access: #{UserVehicleScope.unscoped.kept.read_access.count}"
  puts "      - Write Access: #{UserVehicleScope.unscoped.kept.write_access.count}"
  puts "      - Drive Access: #{UserVehicleScope.unscoped.kept.drive_access.count}"
  puts "      - Active: #{UserVehicleScope.unscoped.kept.active.count}"
  puts "      - Expired: #{UserVehicleScope.unscoped.kept.expired.count}"
end

puts "\n  📈 Seeding Statistics:"
puts "    - Node scopes created: #{stats[:node_scopes]}"
puts "    - Vehicle scopes created: #{stats[:vehicle_scopes]}"
puts "    - Memberships activated: #{stats[:activated_memberships]}"

puts "\n  🔍 Sample Access Patterns:"

# Mostrar algunos ejemplos de acceso
active_tenants.first(2).each do |tenant|
  ActsAsTenant.with_tenant(tenant) do
    puts "\n    #{tenant.name}:"

    # Managers con node scopes
    TenantMembership.active.where(role: manager_role).limit(2).each do |m|
      node_count = m.user.user_node_scopes.kept.where(tenant: tenant).count
      puts "      Manager #{m.user.email}: #{node_count} node scopes"
    end

    # Drivers con vehicle scopes
    TenantMembership.active.where(role: driver_role).limit(2).each do |m|
      vehicle_count = m.user.user_vehicle_scopes.kept.active.where(tenant: tenant).count
      puts "      Driver #{m.user.email}: #{vehicle_count} vehicle scopes"
    end
  end
end

puts "\n  ✅ Access scopes seeding completed!"
