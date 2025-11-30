
# app/api/v1/tenant/vehicles_api.rb

module V1
  module Tenant
    class VehiclesApi < Grape::API
      helpers Helpers::AuthenticationHelper
      helpers Helpers::TenantHelper
      helpers Helpers::AuthorizationHelper

      namespace :tenant do
        namespace :vehicles do
          # ============================================
          # LISTAR VEHÍCULOS
          # ============================================
          desc "List vehicles",
                tags: [ "Tenant - Vehicles" ]
          params do
            optional :tenant_id, type: Integer, desc: "Tenant ID (for platform admins)"
            optional :status, type: String, values: Vehicle::STATUSES
            optional :vehicle_type, type: String, values: Vehicle::VEHICLE_TYPES
            optional :node_id, type: Integer, desc: "Filter by organizational node"
            optional :search, type: String, desc: "Search by name, license plate, or fleet number"
            optional :page, type: Integer, default: 1
            optional :per_page, type: Integer, default: 25, values: 1..100
          end
          get do
            authenticate!

            # Determinar tenant
            target_tenant = if current_user.platform_admin?
              unless params[:tenant_id]
                api_error(message: "Platform admins must provide tenant_id", status: 400)
              end
              ::Tenant.find(params[:tenant_id])
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            # Obtener vehículos usando policy scope
            vehicles = ActsAsTenant.with_tenant(target_tenant) do
              policy_scope(
                Vehicle.includes(:organizational_node),
                policy_scope_class: VehiclePolicy::Scope
              )
            end

            # Aplicar query con filtros
            vehicles = VehiclesQuery.new(
              vehicles,
              params: declared(params),
              user: current_user
            ).call

            # Paginación
            vehicles = vehicles.page(params[:page]).per(params[:per_page])

            success_response(
              data: vehicles.map { |v|
                Entities::VehicleEntity.represent(
                  v,
                  show_details: true,
                  show_status: true,
                  show_organization: true
                )
              },
              meta: {
                current_page: vehicles.current_page,
                total_pages: vehicles.total_pages,
                total_count: vehicles.total_count,
                per_page: params[:per_page]
              }
            )
          end

          # ============================================
          # VER VEHÍCULO
          # ============================================
          desc "Get vehicle details",
                tags: [ "Tenant - Vehicles" ]
          params do
            requires :id, type: Integer
            optional :tenant_id, type: Integer, desc: "Tenant ID (for platform admins)"
          end
          get ":id" do
            authenticate!

            vehicle = Vehicle.find(params[:id])

            # Validar acceso
            if current_user.platform_admin?
              # OK
            elsif current_tenant && vehicle.tenant_id == current_tenant.id
              # OK
            else
              api_error(message: "Vehicle not found or access denied", status: 404)
            end

            authorize!(vehicle, :show?, policy_class: VehiclePolicy)

            success_response(
              data: Entities::VehicleEntity.represent(
                vehicle,
                show_details: true,
                show_status: true,
                show_organization: true,
                include_node: true,
                show_timestamps: true
              )
            )
          end

          # ============================================
          # CREAR VEHÍCULO
          # ============================================
          desc "Create vehicle",
                tags: [ "Tenant - Vehicles" ]
          params do
            optional :tenant_id, type: Integer, desc: "Tenant ID (for platform admins)"
            requires :name, type: String
            requires :license_plate, type: String
            optional :vin, type: String
            optional :fleet_number, type: String
            optional :vehicle_type, type: String, values: Vehicle::VEHICLE_TYPES
            optional :make, type: String
            optional :model, type: String
            optional :year, type: Integer
            optional :color, type: String
            optional :fuel_type, type: String, values: Vehicle::FUEL_TYPES
            optional :fuel_capacity, type: Float
            optional :passenger_capacity, type: Integer
            optional :organizational_node_id, type: Integer
            optional :purchase_date, type: Date
            optional :registration_expires_at, type: Date
            optional :insurance_expires_at, type: Date
            optional :odometer, type: Integer
          end
          post do
            authenticate!

            # Determinar tenant
            target_tenant = if current_user.platform_admin?
              unless params[:tenant_id]
                api_error(message: "Platform admins must provide tenant_id", status: 400)
              end
              ::Tenant.find(params[:tenant_id])
            else
              require_tenant!
              verify_tenant_access!
              current_tenant
            end

            # Autorizar
            temp_vehicle = Vehicle.new(tenant: target_tenant)
            authorize!(temp_vehicle, :create?, policy_class: VehiclePolicy)

            result = ::Tenant::Vehicles::CreateService.call(
              params: declared(params).except(:tenant_id),
              tenant: target_tenant,
              current_user: current_user
            )

            if result.success?
              status 201
              success_response(
                data: Entities::VehicleEntity.represent(
                  result.data,
                  show_details: true
                ),
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # ACTUALIZAR VEHÍCULO
          # ============================================
          desc "Update vehicle",
                tags: [ "Tenant - Vehicles" ]
          params do
            requires :id, type: Integer
            optional :name, type: String
            optional :vehicle_type, type: String, values: Vehicle::VEHICLE_TYPES
            optional :make, type: String
            optional :model, type: String
            optional :year, type: Integer
            optional :status, type: String, values: Vehicle::STATUSES
            optional :color, type: String
            optional :fuel_type, type: String, values: Vehicle::FUEL_TYPES
            optional :organizational_node_id, type: Integer
            optional :registration_expires_at, type: Date
            optional :insurance_expires_at, type: Date
            optional :last_maintenance_date, type: Date
            optional :odometer, type: Integer
          end
          patch ":id" do
            authenticate!

            vehicle = Vehicle.find(params[:id])
            authorize!(vehicle, :update?, policy_class: VehiclePolicy)

            result = ::Tenant::Vehicles::UpdateService.call(
              vehicle: vehicle,
              params: declared(params).except(:id),
              current_user: current_user
            )

            if result.success?
              success_response(
                data: Entities::VehicleEntity.represent(result.data, show_details: true),
                message: result.message
              )
            else
              api_error(message: result.message, errors: result.errors, status: 422)
            end
          end

          # ============================================
          # ELIMINAR VEHÍCULO
          # ============================================
          desc "Delete vehicle",
                tags: [ "Tenant - Vehicles" ]
          params do
            requires :id, type: Integer
          end
          delete ":id" do
            authenticate!

            vehicle = Vehicle.find(params[:id])
            authorize!(vehicle, :destroy?, policy_class: VehiclePolicy)

            vehicle.discard!

            success_response(message: "Vehicle deleted successfully")
          end
        end
      end
    end
  end
end
