# frozen_string_literal: true

# db/seeds/02_users.rb
# Usuarios base del sistema con diferentes estados

puts "\n👥 Creating Base Users..."

# Configuración
DEFAULT_PASSWORD = 'Password123!'

# ============================================
# USUARIOS VERIFICADOS (ACTIVOS)
# ============================================

puts "\n  Active & Verified Users:"

john = User.create_with(
  first_name: 'John',
  last_name: 'Doe',
  password: DEFAULT_PASSWORD,
  password_confirmation: DEFAULT_PASSWORD,
  phone: '+34600000001',
  email_verified_at: 2.months.ago,
  last_login_at: 1.day.ago,
  avatar_url: 'https://ui-avatars.com/api/?name=John+Doe'
).find_or_create_by!(email: 'john.doe@example.com')
puts "    ✓ john.doe@example.com (verified, active)"

jane = User.create_with(
  first_name: 'Jane',
  last_name: 'Smith',
  password: DEFAULT_PASSWORD,
  password_confirmation: DEFAULT_PASSWORD,
  phone: '+34600000002',
  email_verified_at: 1.month.ago,
  last_login_at: 2.hours.ago,
  avatar_url: 'https://ui-avatars.com/api/?name=Jane+Smith'
).find_or_create_by!(email: 'jane.smith@example.com')
puts "    ✓ jane.smith@example.com (verified, active)"

carlos = User.create_with(
  first_name: 'Carlos',
  last_name: 'García',
  password: DEFAULT_PASSWORD,
  password_confirmation: DEFAULT_PASSWORD,
  phone: '+34600000003',
  email_verified_at: 3.weeks.ago,
  last_login_at: 5.days.ago,
  avatar_url: 'https://ui-avatars.com/api/?name=Carlos+Garcia'
).find_or_create_by!(email: 'carlos.garcia@example.com')
puts "    ✓ carlos.garcia@example.com (verified, active)"

# ============================================
# USUARIOS NO VERIFICADOS
# ============================================

puts "\n  Unverified Users:"

unverified1 = User.create_with(
  first_name: 'María',
  last_name: 'López',
  password: DEFAULT_PASSWORD,
  password_confirmation: DEFAULT_PASSWORD,
  phone: '+34600000004',
  email_verified_at: nil
).find_or_create_by!(email: 'maria.lopez@example.com')
puts "    ✓ maria.lopez@example.com (NOT verified)"

unverified2 = User.create_with(
  first_name: 'Pedro',
  last_name: 'Martínez',
  password: DEFAULT_PASSWORD,
  password_confirmation: DEFAULT_PASSWORD,
  phone: '+34600000005',
  email_verified_at: nil
).find_or_create_by!(email: 'pedro.martinez@example.com')
puts "    ✓ pedro.martinez@example.com (NOT verified)"

# ============================================
# USUARIOS CON INVITACIÓN PENDIENTE
# ============================================

puts "\n  Users with Pending Invitations:"

invited1 = User.create_with(
  first_name: 'Ana',
  last_name: 'Rodríguez',
  password: DEFAULT_PASSWORD,
  password_confirmation: DEFAULT_PASSWORD,
  invitation_token: SecureRandom.hex(32),
  invitation_expires_at: 7.days.from_now,
  invited_by: john
).find_or_create_by!(email: 'ana.rodriguez@example.com')
puts "    ✓ ana.rodriguez@example.com (invitation pending)"

invited2 = User.create_with(
  first_name: 'Luis',
  last_name: 'Fernández',
  password: DEFAULT_PASSWORD,
  password_confirmation: DEFAULT_PASSWORD,
  invitation_token: SecureRandom.hex(32),
  invitation_expires_at: 5.days.from_now,
  invited_by: jane
).find_or_create_by!(email: 'luis.fernandez@example.com')
puts "    ✓ luis.fernandez@example.com (invitation pending)"

# ============================================
# USUARIOS CON INVITACIÓN EXPIRADA
# ============================================

puts "\n  Users with Expired Invitations:"

expired_invite = User.create_with(
  first_name: 'Expired',
  last_name: 'Invitation',
  password: DEFAULT_PASSWORD,
  password_confirmation: DEFAULT_PASSWORD,
  invitation_token: SecureRandom.hex(32),
  invitation_expires_at: 10.days.ago,
  invited_by: john
).find_or_create_by!(email: 'expired@example.com')
puts "    ✓ expired@example.com (invitation EXPIRED)"

# ============================================
# USUARIOS CON INVITACIÓN ACEPTADA
# ============================================

puts "\n  Users with Accepted Invitations:"

accepted = User.create_with(
  first_name: 'Accepted',
  last_name: 'User',
  password: DEFAULT_PASSWORD,
  password_confirmation: DEFAULT_PASSWORD,
  email_verified_at: 1.week.ago,
  invitation_accepted_at: 1.week.ago,
  invited_by: john
).find_or_create_by!(email: 'accepted@example.com')
puts "    ✓ accepted@example.com (invitation accepted)"

# ============================================
# USUARIO BLOQUEADO (LOCKED)
# ============================================

puts "\n  Locked Users:"

locked_user = User.create_with(
  first_name: 'Locked',
  last_name: 'User',
  password: DEFAULT_PASSWORD,
  password_confirmation: DEFAULT_PASSWORD,
  email_verified_at: 2.months.ago,
  failed_attempts: 5,
  locked_at: 1.day.ago
).find_or_create_by!(email: 'locked@example.com')
puts "    ✓ locked@example.com (account LOCKED)"

# ============================================
# USUARIO SOFT DELETED
# ============================================

puts "\n  Soft Deleted Users:"

deleted_user = User.create_with(
  first_name: 'Deleted',
  last_name: 'User',
  password: DEFAULT_PASSWORD,
  password_confirmation: DEFAULT_PASSWORD,
  email_verified_at: 3.months.ago,
  deleted_at: 1.week.ago,
  deleted_by: john.id
).find_or_create_by!(email: 'deleted@example.com')
puts "    ✓ deleted@example.com (soft DELETED)"

# ============================================
# USUARIOS ADICIONALES PARA VARIEDAD
# ============================================

puts "\n  Additional Test Users:"

[
  { first: 'Laura', last: 'Sánchez', email: 'laura.sanchez@example.com' },
  { first: 'Miguel', last: 'Torres', email: 'miguel.torres@example.com' },
  { first: 'Isabel', last: 'Ramírez', email: 'isabel.ramirez@example.com' },
  { first: 'David', last: 'Moreno', email: 'david.moreno@example.com' },
  { first: 'Carmen', last: 'Jiménez', email: 'carmen.jimenez@example.com' }
].each_with_index do |user_data, index|
  User.create_with(
    first_name: user_data[:first],
    last_name: user_data[:last],
    password: DEFAULT_PASSWORD,
    password_confirmation: DEFAULT_PASSWORD,
    phone: "+3460000#{1010 + index}",
    email_verified_at: rand(1..60).days.ago,
    last_login_at: rand(1..10).days.ago
  ).find_or_create_by!(email: user_data[:email])
  puts "    ✓ #{user_data[:email]}"
end

# ============================================
# RESUMEN
# ============================================

puts "\n  📊 Users Summary:"
puts "    - Total Users: #{User.count}"
puts "    - Verified: #{User.verified.count}"
puts "    - Unverified: #{User.unverified.count}"
puts "    - Pending Invitations: #{User.pending_invitation.count}"
puts "    - Accepted Invitations: #{User.invitation_accepted.count}"
puts "    - Locked: #{User.where.not(locked_at: nil).count}"
puts "    - Soft Deleted: #{User.discarded.count}"
puts "    - Active: #{User.kept.count}"

puts "\n  🔐 Login Credentials:"
puts "    Email: [any-user]@example.com"
puts "    Password: #{DEFAULT_PASSWORD}"
