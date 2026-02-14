# db/seeds/04_tenants.rb
# Tenants con diferentes estados, planes y membresías
# CORREGIDO: Solo crear ADMINS (sin scopes) y usuarios INVITED

puts "\n🏢 Creating Tenants..."

# Roles
admin_role = Role.find_by!(slug: 'tenant_admin')
manager_role = Role.find_by!(slug: 'tenant_manager')
driver_role = Role.find_by!(slug: 'tenant_driver')
viewer_role = Role.find_by(slug: 'tenant_viewer')
coordinator_role = Role.find_by(slug: 'fleet_coordinator')

# ============================================
# HELPER PARA CREAR MEMBRESÍAS
# ============================================

def create_tenant_membership(user, tenant, role, options = {})
  defaults = {
    # ⚠️ CRÍTICO: Si el rol requiere scopes, crear como INVITED
    # Se activará después de crear los scopes en 07_scopes.rb
    status: role.requires_any_scope? ? 'invited' : 'active',
    created_by: options[:created_by],
    is_primary_admin: options[:is_primary_admin] || false,
    is_default: options[:is_default] || false
  }

  # Si se pasa status explícito, usarlo
  defaults[:status] = options[:status] if options[:status]

  TenantMembership.create_with(defaults.merge(role: role))
    .find_or_create_by!(user: user, tenant: tenant, role: role)
end

# ============================================
# TENANT 1: TRIAL (Acme Corp)
# ============================================

puts "\n  Creating Trial Tenant:"

acme = Tenant.create_with(
  name: 'Acme Corporation',
  legal_name: 'Acme Corporation S.L.',
  tax_id: 'B12345678',
  domain: 'acme.example.com',
  address: 'Calle Mayor 123',
  city: 'Madrid',
  state: 'Madrid',
  postal_code: '28013',
  country: 'ES',
  timezone: 'Europe/Madrid',
  locale: 'es',
  currency: 'EUR',
  status: 'trial',
  plan: 'trial',
  trial_ends_at: 20.days.from_now,
  max_users: 5,
  max_storage_gb: 10,
  settings: {
    features_enabled: %w[fleet_management basic_reporting],
    notifications_enabled: true,
    theme: 'light'
  },
  metadata: {
    industry: 'logistics',
    company_size: 'small',
    onboarding_completed: false
  }
).find_or_create_by!(slug: 'acme-corp')

puts "    ✓ Acme Corporation (TRIAL - expires in 20 days)"

# ============ ADMIN PRINCIPAL (Acme) - NO REQUIERE SCOPES ============
acme_admin = User.create_with(
  first_name: 'María',
  last_name: 'García',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600111111',
  email_verified_at: Time.current
).find_or_create_by!(email: 'maria.garcia@acme.com')

create_tenant_membership(
  acme_admin, acme, admin_role,
  created_by: acme_admin.id,
  is_primary_admin: true,
  is_default: true,
  status: 'active' # Admin NO requiere scopes
)
puts "      Admin: maria.garcia@acme.com (active)"

# ============ MANAGER (Acme) - REQUIERE NODE SCOPES ============
acme_manager = User.create_with(
  first_name: 'Carlos',
  last_name: 'López',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600111112',
  email_verified_at: Time.current
).find_or_create_by!(email: 'carlos.lopez@acme.com')

# Manager requiere node scopes -> crear como INVITED
create_tenant_membership(
  acme_manager, acme, manager_role,
  created_by: acme_admin.id,
  status: 'invited' # Se activará en 07_scopes.rb después de asignar nodos
)
puts "      Manager: carlos.lopez@acme.com (invited - pending scopes)"

# ============ DRIVER (Acme) - REQUIERE VEHICLE SCOPES ============
acme_driver = User.create_with(
  first_name: 'Ana',
  last_name: 'Rodríguez',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600111113'
).find_or_create_by!(email: 'ana.rodriguez@acme.com')

# Driver requiere vehicle scopes -> crear como INVITED
create_tenant_membership(
  acme_driver, acme, driver_role,
  created_by: acme_admin.id,
  status: 'invited' # Se activará en 07_scopes.rb después de asignar vehículos
)
puts "      Driver: ana.rodriguez@acme.com (invited - pending scopes)"

# ============================================
# TENANT 2: ACTIVE - BASIC PLAN (Tech Startup)
# ============================================

puts "\n  Creating Active Tenant (Basic Plan):"

techstart = Tenant.create_with(
  name: 'Tech Startup Inc',
  legal_name: 'Tech Startup Inc.',
  tax_id: 'B87654321',
  domain: 'techstartup.example.com',
  address: 'Passeig de Gràcia 100',
  city: 'Barcelona',
  state: 'Catalonia',
  postal_code: '08008',
  country: 'ES',
  timezone: 'Europe/Madrid',
  locale: 'ca',
  currency: 'EUR',
  status: 'active',
  plan: 'basic',
  subscription_starts_at: 3.months.ago,
  subscription_ends_at: 9.months.from_now,
  max_users: 10,
  max_storage_gb: 50,
  settings: {
    features_enabled: %w[fleet_management advanced_reporting api_access],
    notifications_enabled: true,
    theme: 'dark'
  }
).find_or_create_by!(slug: 'tech-startup')

puts "    ✓ Tech Startup Inc (ACTIVE - Basic Plan)"

# ============ ADMIN (Tech Startup) ============
tech_admin = User.create_with(
  first_name: 'Joan',
  last_name: 'Martínez',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600222222',
  email_verified_at: 3.months.ago
).find_or_create_by!(email: 'joan.martinez@techstartup.com')

create_tenant_membership(
  tech_admin, techstart, admin_role,
  created_by: tech_admin.id,
  is_primary_admin: true,
  is_default: true,
  status: 'active'
)
puts "      Admin: joan.martinez@techstartup.com (active)"

# ============ MANAGER (Tech Startup) ============
tech_manager = User.create_with(
  first_name: 'Anna',
  last_name: 'Puig',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600222223',
  email_verified_at: 2.months.ago
).find_or_create_by!(email: 'anna.puig@techstartup.com')

create_tenant_membership(
  tech_manager, techstart, manager_role,
  created_by: tech_admin.id,
  status: 'invited'
)
puts "      Manager: anna.puig@techstartup.com (invited - pending scopes)"

# ============ DRIVER (Tech Startup) ============
tech_driver = User.create_with(
  first_name: 'Sergi',
  last_name: 'Rovira',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600222224',
  email_verified_at: 1.month.ago
).find_or_create_by!(email: 'sergi.rovira@techstartup.com')

create_tenant_membership(
  tech_driver, techstart, driver_role,
  created_by: tech_admin.id,
  status: 'invited'
)
puts "      Driver: sergi.rovira@techstartup.com (invited - pending scopes)"

# ============================================
# TENANT 3: ACTIVE - PROFESSIONAL PLAN (Global Logistics)
# ============================================

puts "\n  Creating Active Tenant (Professional Plan):"

logistics = Tenant.create_with(
  name: 'Global Logistics Pro',
  legal_name: 'Global Logistics Pro S.A.',
  tax_id: 'A11223344',
  domain: 'globallogistics.example.com',
  address: 'Avenida Diagonal 500',
  city: 'Barcelona',
  state: 'Catalonia',
  postal_code: '08006',
  country: 'ES',
  timezone: 'Europe/Madrid',
  locale: 'es',
  currency: 'EUR',
  status: 'active',
  plan: 'professional',
  subscription_starts_at: 1.year.ago,
  subscription_ends_at: 1.year.from_now,
  max_users: 50,
  max_storage_gb: 200,
  settings: {
    features_enabled: %w[fleet_management advanced_reporting api_access custom_integrations multi_location],
    notifications_enabled: true
  }
).find_or_create_by!(slug: 'global-logistics')

puts "    ✓ Global Logistics Pro (ACTIVE - Professional Plan)"

# ============ ADMIN PRINCIPAL (Logistics) ============
logistics_admin = User.create_with(
  first_name: 'Patricia',
  last_name: 'Torres',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600333333',
  email_verified_at: 1.year.ago
).find_or_create_by!(email: 'patricia.torres@globallogistics.com')

create_tenant_membership(
  logistics_admin, logistics, admin_role,
  created_by: logistics_admin.id,
  is_primary_admin: true,
  is_default: true,
  status: 'active'
)
puts "      Admin: patricia.torres@globallogistics.com (active)"

# ============ FLEET COORDINATOR (Logistics) ============
if coordinator_role
  fleet_coord = User.create_with(
    first_name: 'Jorge',
    last_name: 'Ruiz',
    password: 'Password123!',
    password_confirmation: 'Password123!',
    phone: '+34600333334',
    email_verified_at: 10.months.ago
  ).find_or_create_by!(email: 'jorge.ruiz@globallogistics.com')

  create_tenant_membership(
    fleet_coord, logistics, coordinator_role,
    created_by: logistics_admin.id,
    status: 'invited'
  )
  puts "      Fleet Coordinator: jorge.ruiz@globallogistics.com (invited - pending scopes)"
end

# ============ MANAGERS - 3 MANAGERS ============
3.times do |i|
  manager = User.create_with(
    first_name: %w[David Laura Miguel][i],
    last_name: %w[Moreno Sánchez Torres][i],
    password: 'Password123!',
    password_confirmation: 'Password123!',
    phone: "+3460033#{3340 + i}",
    email_verified_at: rand(1..11).months.ago
  ).find_or_create_by!(email: "#{%w[david.moreno laura.sanchez miguel.torres][i]}@globallogistics.com")

  create_tenant_membership(
    manager, logistics, manager_role,
    created_by: logistics_admin.id,
    status: 'invited'
  )
end
puts "      Managers: 3 (invited - pending scopes)"

# ============ DRIVERS - 5 DRIVERS ============
5.times do |i|
  driver = User.create_with(
    first_name: "Driver",
    last_name: "#{i + 1}",
    password: 'Password123!',
    password_confirmation: 'Password123!',
    phone: "+3460033#{3350 + i}",
    email_verified_at: rand(1..6).months.ago
  ).find_or_create_by!(email: "driver#{i + 1}@globallogistics.com")

  create_tenant_membership(
    driver, logistics, driver_role,
    created_by: logistics_admin.id,
    status: 'invited'
  )
end
puts "      Drivers: 5 (invited - pending scopes)"

# ============ VIEWER ============
if viewer_role
  viewer = User.create_with(
    first_name: 'Monitor',
    last_name: 'Analytics',
    password: 'Password123!',
    password_confirmation: 'Password123!',
    phone: '+34600333366',
    email_verified_at: 6.months.ago
  ).find_or_create_by!(email: 'monitor.analytics@globallogistics.com')

  create_tenant_membership(
    viewer, logistics, viewer_role,
    created_by: logistics_admin.id,
    status: 'invited'
  )
  puts "      Viewer: monitor.analytics@globallogistics.com (invited - pending scopes)"
end

# ============================================
# USUARIO CON MÚLTIPLES MEMBRESÍAS (CROSS-TENANT)
# ============================================

puts "\n  Creating User with Multiple Memberships:"

multi_tenant_user = User.create_with(
  first_name: 'Operativo',
  last_name: 'Universal',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34600999999',
  email_verified_at: 5.months.ago
).find_or_create_by!(email: 'operativo.universal@example.com')

# Manager en Acme (invited)
create_tenant_membership(
  multi_tenant_user, acme, manager_role,
  created_by: acme_admin.id,
  status: 'invited'
)

# Driver en Tech Startup (invited)
create_tenant_membership(
  multi_tenant_user, techstart, driver_role,
  created_by: tech_admin.id,
  status: 'invited'
)

# Viewer en Logistics (invited)
if viewer_role
  create_tenant_membership(
    multi_tenant_user, logistics, viewer_role,
    created_by: logistics_admin.id,
    status: 'invited'
  )
end

puts "    ✓ operativo.universal@example.com"
puts "      - Manager @ Acme Corporation (invited)"
puts "      - Driver @ Tech Startup Inc (invited)"
puts "      - Viewer @ Global Logistics Pro (invited)" if viewer_role

# ============================================
# TENANT 4: SUSPENDED
# ============================================

puts "\n  Creating Suspended Tenant:"

suspended = Tenant.create_with(
  name: 'Suspended Company Ltd',
  legal_name: 'Suspended Company Ltd',
  tax_id: 'B99887766',
  address: 'Calle Suspended 999',
  city: 'Valencia',
  country: 'ES',
  timezone: 'Europe/Madrid',
  locale: 'es',
  currency: 'EUR',
  status: 'suspended',
  plan: 'basic',
  subscription_starts_at: 6.months.ago,
  metadata: {
    suspension_reason: 'Payment overdue',
    suspended_at: 1.week.ago
  }
).find_or_create_by!(slug: 'suspended-company')

suspended_admin = User.create_with(
  first_name: 'Suspended',
  last_name: 'Admin',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  email_verified_at: 6.months.ago
).find_or_create_by!(email: 'admin@suspended.com')

TenantMembership.create_with(
  tenant: suspended,
  role: admin_role,
  status: 'suspended',
  is_primary_admin: true,
  created_by: suspended_admin.id
).find_or_create_by!(user: suspended_admin, tenant: suspended, role: admin_role)

puts "    ✓ Suspended Company Ltd (SUSPENDED - payment issue)"

# ============================================
# TENANT 5: CANCELLED
# ============================================

puts "\n  Creating Cancelled Tenant:"

cancelled = Tenant.create_with(
  name: 'Cancelled Corp',
  legal_name: 'Cancelled Corp S.L.',
  tax_id: 'B55443322',
  country: 'ES',
  status: 'cancelled',
  plan: 'trial',
  subscription_ends_at: 2.weeks.ago,
  metadata: {
    cancellation_reason: 'Switched to competitor',
    cancelled_at: 2.weeks.ago
  }
).find_or_create_by!(slug: 'cancelled-corp')

puts "    ✓ Cancelled Corp (CANCELLED - churned)"

# ============================================
# TENANT 6: ENTERPRISE
# ============================================

puts "\n  Creating Enterprise Tenant:"

enterprise = Tenant.create_with(
  name: 'Enterprise Solutions Mega Corp',
  legal_name: 'Enterprise Solutions International S.A.',
  tax_id: 'A00112233',
  domain: 'enterprise.example.com',
  address: 'Torre Empresarial, Piso 25',
  city: 'Madrid',
  state: 'Madrid',
  postal_code: '28046',
  country: 'ES',
  timezone: 'Europe/Madrid',
  locale: 'es',
  currency: 'EUR',
  status: 'active',
  plan: 'enterprise',
  subscription_starts_at: 2.years.ago,
  max_users: 1000,
  max_storage_gb: 1000,
  settings: {
    features_enabled: %w[
      fleet_management
      advanced_reporting
      api_access
      custom_integrations
      multi_location
      white_label
      priority_support
      sla_99_9
    ],
    custom_domain_enabled: true,
    sso_enabled: true
  }
).find_or_create_by!(slug: 'enterprise-mega')
puts "    ✓ Enterprise Solutions Mega Corp (ACTIVE - Enterprise Plan)"

# ============ ADMIN (Enterprise) ============
enterprise_admin = User.create_with(
  first_name: 'Enterprise',
  last_name: 'Admin',
  password: 'Password123!',
  password_confirmation: 'Password123!',
  phone: '+34900444444',
  email_verified_at: 2.years.ago
).find_or_create_by!(email: 'admin@enterprise.com')

create_tenant_membership(
  enterprise_admin, enterprise, admin_role,
  created_by: enterprise_admin.id,
  is_primary_admin: true,
  is_default: true,
  status: 'active'
)
puts "      Admin: admin@enterprise.com (active)"

# ============ MANAGERS (Enterprise - 5 managers) ============
5.times do |i|
  manager = User.create_with(
    first_name: "Regional",
    last_name: "Manager #{i + 1}",
    password: 'Password123!',
    password_confirmation: 'Password123!',
    phone: "+3490044#{4440 + i}",
    email_verified_at: rand(1..24).months.ago
  ).find_or_create_by!(email: "manager#{i + 1}@enterprise.com")

  create_tenant_membership(
    manager, enterprise, manager_role,
    created_by: enterprise_admin.id,
    status: 'invited'
  )
end
puts "      Managers: 5 (invited - pending scopes)"

# ============ DRIVERS (Enterprise - 10 drivers) ============
10.times do |i|
  driver = User.create_with(
    first_name: "Enterprise",
    last_name: "Driver #{i + 1}",
    password: 'Password123!',
    password_confirmation: 'Password123!',
    phone: "+3490044#{4450 + i}",
    email_verified_at: rand(1..12).months.ago
  ).find_or_create_by!(email: "enterprise_driver#{i + 1}@enterprise.com")

  create_tenant_membership(
    driver, enterprise, driver_role,
    created_by: enterprise_admin.id,
    status: 'invited'
  )
end
puts "      Drivers: 10 (invited - pending scopes)"

# ============================================
# RESUMEN
# ============================================

puts "\n  📊 Tenants Summary:"
puts "    - Total Tenants: #{Tenant.count}"
puts "    - By Status:"
puts "      - Trial: #{Tenant.trial.count}"
puts "      - Active: #{Tenant.active.count}"
puts "      - Suspended: #{Tenant.suspended.count}"
puts "      - Cancelled: #{Tenant.cancelled.count}"
puts "    - By Plan:"
puts "      - Trial: #{Tenant.by_plan('trial').count}"
puts "      - Basic: #{Tenant.by_plan('basic').count}"
puts "      - Professional: #{Tenant.by_plan('professional').count}"
puts "      - Enterprise: #{Tenant.by_plan('enterprise').count}"

puts "\n  👥 Tenant Memberships Summary:"
puts "    - Total Memberships: #{TenantMembership.count}"
puts "    - Active: #{TenantMembership.active.count}"
puts "    - Invited: #{TenantMembership.invited.count}"
puts "    - Suspended: #{TenantMembership.suspended.count}"

puts "\n  👤 Users with Multiple Memberships:"
User.joins(:tenant_memberships)
  .select('users.*, COUNT(tenant_memberships.id) as membership_count')
  .group('users.id')
  .having('COUNT(tenant_memberships.id) > 1')
  .order('membership_count DESC')
  .each do |user|
    memberships = user.tenant_memberships.includes(:tenant, :role)
    puts "    #{user.email} (#{memberships.count} memberships):"
    memberships.each do |m|
      puts "      - #{m.tenant.name}: #{m.role.name} (#{m.status})"
    end
  end

puts "\n  🏢 Tenant Access Info:"
Tenant.kept.each do |tenant|
  primary_admin = tenant.primary_admin
  puts "    #{tenant.name} (#{tenant.plan.upcase} - #{tenant.status})"
  puts "      Primary Admin: #{primary_admin&.email || 'N/A'}"
  puts "      Members: #{tenant.tenant_memberships.kept.count}/#{tenant.max_users}"

  # Contar por rol
  role_counts = tenant.tenant_memberships.kept.joins(:role)
    .group('roles.name', 'tenant_memberships.status')
    .count

  role_counts.each do |(role_name, status), count|
    puts "      - #{role_name} (#{status}): #{count}"
  end
end

puts "\n  ⚠️  IMPORTANT NOTE:"
puts "     Roles requiring scopes (Manager, Driver, Viewer, Coordinator)"
puts "     are created as 'invited' and will be activated in 07_scopes.rb"
puts "     after proper scope assignment (nodes or vehicles)"
