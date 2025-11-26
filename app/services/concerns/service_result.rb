# App/services/concerns/service_result.rb

# Objeto de resultado estándar para servicios
# Proporciona una interfaz consistente para retornar resultados de operaciones
#
# Uso en servicios:
#   class CreateUserService
#     def call
#       user = User.new(params)
#       if user.save
#         ServiceResult.success(data: user, message: 'User created')
#       else
#         ServiceResult.failure(errors: user.errors.full_messages)
#       end
#     end
#   end
#
# Uso en controllers/APIs:
#   result = CreateUserService.call(params)
#   if result.success?
#     render json: result.data
#   else
#     render json: { errors: result.errors }, status: :unprocessable_entity
#   end

class ServiceResult
  attr_reader :success, :data, :errors, :message, :meta

  def initialize(success:, data: nil, errors: nil, message: nil, meta: nil)
    @success = success
    @data = data
    @errors = errors || []
    @message = message
    @meta = meta || {}
  end

  # Métodos de conveniencia para crear resultados

  def self.success(data: nil, message: nil, meta: nil)
    new(
      success: true,
      data: data,
      message: message,
      meta: meta
    )
  end

  def self.failure(errors: nil, message: nil, data: nil, meta: nil)
    # Normalizar errores a array
    normalized_errors = case errors
    when String
                          [ errors ]
    when Hash
                          errors.values.flatten
    when Array
                          errors
    when ActiveModel::Errors
                          errors.full_messages
    else
                          [ "Unknown error occurred" ]
    end

    new(
      success: false,
      errors: normalized_errors,
      message: message || normalized_errors.first,
      data: data,
      meta: meta
    )
  end

  # Predicados

  def success?
    @success == true
  end

  def failure?
    !success?
  end

  def has_data?
    @data.present?
  end

  def has_errors?
    @errors.present?
  end

  # Conversión a hash (útil para APIs)

  def to_h
    hash = {
      success: @success
    }

    hash[:data] = @data if @data.present?
    hash[:message] = @message if @message.present?
    hash[:errors] = @errors if @errors.present?
    hash[:meta] = @meta if @meta.present?

    hash
  end

  def to_json(*args)
    to_h.to_json(*args)
  end

  # Acceso a datos con métodos delegation

  def method_missing(method_name, *args, &block)
    if @data.respond_to?(method_name)
      @data.public_send(method_name, *args, &block)
    else
      super
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    @data.respond_to?(method_name) || super
  end

  # Operadores útiles

  # Permite encadenar operaciones
  # result = service1.call.then { |data| service2.call(data) }
  def then
    if success? && block_given?
      yield(@data)
    else
      self
    end
  end

  # Rescue de errores automático
  # result = service.call.rescue_from(ActiveRecord::RecordNotFound) { |e| ... }
  def rescue_from(exception_class, &block)
    self
  rescue exception_class => e
    block.call(e) if block_given?
    ServiceResult.failure(errors: e.message)
  end

  # Helpers para debugging

  def inspect
    "#<ServiceResult success: #{@success}, data: #{@data.inspect}, errors: #{@errors.inspect}>"
  end
end

# # Módulo para incluir en servicios base
# module ServiceResultHelper
#   # Crear resultado de éxito
#   def success(data: nil, message: nil, meta: nil)
#     ServiceResult.success(data: data, message: message, meta: meta)
#   end

#   # Crear resultado de fallo
#   def failure(errors: nil, message: nil, data: nil, meta: nil)
#     ServiceResult.failure(errors: errors, message: message, data: data, meta: meta)
#   end

#   # Ejecutar bloque y retornar ServiceResult automáticamente
#   def result_from
#     yield
#   rescue ActiveRecord::RecordInvalid => e
#     failure(errors: e.record.errors.full_messages)
#   rescue ActiveRecord::RecordNotFound => e
#     failure(errors: "Record not found", message: e.message)
#   rescue StandardError => e
#     Rails.logger.error("[ServiceError] #{e.class.name}: #{e.message}")
#     Rails.logger.error(e.backtrace.join("\n"))
#     failure(errors: "An error occurred", message: e.message)
#   end
# end
