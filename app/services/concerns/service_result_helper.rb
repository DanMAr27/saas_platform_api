# Módulo para incluir en servicios base
module ServiceResultHelper
  # Crear resultado de éxito
  def success(data: nil, message: nil, meta: nil)
    ServiceResult.success(data: data, message: message, meta: meta)
  end

  # Crear resultado de fallo
  def failure(errors: nil, message: nil, data: nil, meta: nil)
    ServiceResult.failure(errors: errors, message: message, data: data, meta: meta)
  end

  # Ejecutar bloque y retornar ServiceResult automáticamente
  def result_from
    yield
  rescue ActiveRecord::RecordInvalid => e
    failure(errors: e.record.errors.full_messages)
  rescue ActiveRecord::RecordNotFound => e
    failure(errors: "Record not found", message: e.message)
  rescue StandardError => e
    Rails.logger.error("[ServiceError] #{e.class.name}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    failure(errors: "An error occurred", message: e.message)
  end
end
