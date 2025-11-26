# db/seeds.rb

# Directorio donde se encuentran tus archivos de seeds
seeds_dir = Rails.root.join('db', 'seeds')

puts "Starting database seeding..."

# Iterar sobre todos los archivos .rb en la carpeta db/seeds/
# Esto asegura que se carguen en orden alfabético (por eso usas 01_, 02_, etc.)
Dir.glob(seeds_dir.join('**', '*.rb')).sort.each do |file|
  puts "\nProcessing seed file: #{File.basename(file)}"
  load(file)
end

puts "\nDatabase seeding finished successfully! 🎉"
