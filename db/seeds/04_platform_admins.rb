# frozen_string_literal: true

# Seeds para Fase 3: Platform Admins
# Crea Super Admin y Support Admin

puts "\n==== Seeding Platform Admins (Phase 3) ===="

# Asegurarse de que los roles existan
super_admin_role = Role.find_by(slug: 'super_admin')
support_admin_role = Role.find_by(slug: 'support_admin')

unless super_admin_role && support_admin_role
  puts "✗ Error: Platform roles not found. Run 03_roles.rb first."
  exit
end

# ============================================
# SUPER ADMIN
# ============================================

super_admin_email = ENV.fetch('SUPER_ADMIN_EMAIL', 'superadmin@saasplatform.com')
super_admin = User.find_or_initialize_by(email: super_admin_email)

if super_admin.new_record?
  super_admin.assign_attributes(
    first_name: ENV.fetch('SUPER_ADMIN_FIRST_NAME', 'Super'),
    last_name: ENV.fetch('SUPER_ADMIN_LAST_NAME', 'Admin'),
    password: ENV.fetch('SUPER_ADMIN_PASSWORD', 'SuperAdmin123!'),
    password_confirmation: ENV.fetch('SUPER_ADMIN_PASSWORD', 'SuperAdmin123!'),
    phone: '+34600000000',
    email_verified_at: Time.current
  )
  super_admin.save!
  puts "✓ Created Super Admin user: #{super_admin.email}"
else
  puts "⊘ Super Admin user already exists: #{super_admin.email}"
end

# Crear platform membership para super admin
platform_membership = PlatformMembership.find_or_initialize_by(user: super_admin)
if platform_membership.new_record?
  platform_membership.assign_attributes(
    role: super_admin_role,
    context: 'platform',
    mfa_enabled: false, # MFA no es obligatorio para super admin
    can_impersonate: false # Super admin no necesita impersonar, tiene acceso total
  )
  platform_membership.save!
  puts "✓ Created Platform Membership for Super Admin"
else
  puts "⊘ Platform Membership already exists for Super Admin"
end

# ============================================
# SUPPORT ADMIN
# ============================================

support_admin_email = ENV.fetch('SUPPORT_ADMIN_EMAIL', 'support@saasplatform.com')
support_admin = User.find_or_initialize_by(email: support_admin_email)

if support_admin.new_record?
  support_admin.assign_attributes(
    first_name: 'Support',
    last_name: 'Admin',
    password: ENV.fetch('SUPPORT_ADMIN_PASSWORD', 'SupportAdmin123!'),
    password_confirmation: ENV.fetch('SUPPORT_ADMIN_PASSWORD', 'SupportAdmin123!'),
    phone: '+34600000001',
    email_verified_at: Time.current
  )
  support_admin.save!
  puts "✓ Created Support Admin user: #{support_admin.email}"
else
  puts "⊘ Support Admin user already exists: #{support_admin.email}"
end

# Crear platform membership para support admin
support_membership = PlatformMembership.find_or_initialize_by(user: support_admin)
if support_membership.new_record?
  support_membership.assign_attributes(
    role: support_admin_role,
    context: 'platform',
    mfa_enabled: true, # MFA obligatorio para support
    mfa_configured_at: Time.current,
    can_impersonate: true # Support puede impersonar usuarios
  )
  support_membership.save!
  puts "✓ Created Platform Membership for Support Admin"
else
  puts "⊘ Platform Membership already exists for Support Admin"
end

# ============================================
# RESUMEN
# ============================================
puts "\n==== Platform Admins Seeds Summary ===="
puts "Total platform memberships: #{PlatformMembership.count}"
puts "Super Admins: #{PlatformMembership.super_admins.count}"
puts "Support Admins: #{PlatformMembership.support_admins.count}"
puts "\n==== Available Platform Admin Accounts ===="
puts "1. Super Admin"
puts "   - Email: #{super_admin_email}"
puts "   - Password: #{ENV.fetch('SUPER_ADMIN_PASSWORD', 'SuperAdmin123!')}"
puts "   - Can: Full system access, manage all tenants"
puts "\n2. Support Admin"
puts "   - Email: #{support_admin_email}"
puts "   - Password: #{ENV.fetch('SUPPORT_ADMIN_PASSWORD', 'SupportAdmin123!')}"
puts "   - Can: Impersonate users, view all tenants (read-only mostly)"
puts "   - MFA: Required (configured for testing)"
puts "====================================\n"
