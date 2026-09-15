export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      app_users: {
        Row: {
          blocked_at: string | null
          created_at: string
          display_name: string | null
          id: string
          inactivated_at: string | null
          status: string
          updated_at: string
          version: number
        }
        Insert: {
          blocked_at?: string | null
          created_at?: string
          display_name?: string | null
          id: string
          inactivated_at?: string | null
          status?: string
          updated_at?: string
          version?: number
        }
        Update: {
          blocked_at?: string | null
          created_at?: string
          display_name?: string | null
          id?: string
          inactivated_at?: string | null
          status?: string
          updated_at?: string
          version?: number
        }
        Relationships: []
      }
      audit_events: {
        Row: {
          actor_kind: string
          actor_ref: string | null
          actor_user_id: string | null
          authority_kind: string | null
          causation_id: string | null
          command_id: string | null
          correlation_id: string
          entity_id: string | null
          entity_type: string
          event_type: string
          event_version: number
          id: string
          metadata: Json
          occurred_at: string
          reason: string | null
          source: string | null
          tenant_id: string | null
        }
        Insert: {
          actor_kind: string
          actor_ref?: string | null
          actor_user_id?: string | null
          authority_kind?: string | null
          causation_id?: string | null
          command_id?: string | null
          correlation_id?: string
          entity_id?: string | null
          entity_type: string
          event_type: string
          event_version?: number
          id?: string
          metadata?: Json
          occurred_at?: string
          reason?: string | null
          source?: string | null
          tenant_id?: string | null
        }
        Update: {
          actor_kind?: string
          actor_ref?: string | null
          actor_user_id?: string | null
          authority_kind?: string | null
          causation_id?: string | null
          command_id?: string | null
          correlation_id?: string
          entity_id?: string | null
          entity_type?: string
          event_type?: string
          event_version?: number
          id?: string
          metadata?: Json
          occurred_at?: string
          reason?: string | null
          source?: string | null
          tenant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_events_actor_user_id_fkey"
            columns: ["actor_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "audit_events_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      history_entries: {
        Row: {
          actor_kind: string
          actor_ref: string | null
          actor_user_id: string | null
          aggregate_id: string
          aggregate_type: string
          aggregate_version: number | null
          causation_id: string | null
          command_id: string
          command_name: string
          correlation_id: string
          history_type: string
          history_version: number
          human_code: string | null
          id: string
          occurred_at: string
          payload: Json
          source: string
          tenant_id: string
        }
        Insert: {
          actor_kind: string
          actor_ref?: string | null
          actor_user_id?: string | null
          aggregate_id: string
          aggregate_type: string
          aggregate_version?: number | null
          causation_id?: string | null
          command_id: string
          command_name: string
          correlation_id: string
          history_type: string
          history_version?: number
          human_code?: string | null
          id?: string
          occurred_at?: string
          payload?: Json
          source: string
          tenant_id: string
        }
        Update: {
          actor_kind?: string
          actor_ref?: string | null
          actor_user_id?: string | null
          aggregate_id?: string
          aggregate_type?: string
          aggregate_version?: number | null
          causation_id?: string | null
          command_id?: string
          command_name?: string
          correlation_id?: string
          history_type?: string
          history_version?: number
          human_code?: string | null
          id?: string
          occurred_at?: string
          payload?: Json
          source?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "history_entries_actor_user_id_fkey"
            columns: ["actor_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "history_entries_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      permission_catalog: {
        Row: {
          action_code: string
          code: string
          created_at: string
          deprecated_at: string | null
          description_key: string | null
          id: string
          label_key: string
          module_code: string
          required_entitlement_key: string | null
          resource_code: string
          scope: Database["public"]["Enums"]["authorization_scope"]
          status: string
          tenant_delegable: boolean
          updated_at: string
        }
        Insert: {
          action_code: string
          code: string
          created_at?: string
          deprecated_at?: string | null
          description_key?: string | null
          id: string
          label_key: string
          module_code: string
          required_entitlement_key?: string | null
          resource_code: string
          scope: Database["public"]["Enums"]["authorization_scope"]
          status?: string
          tenant_delegable?: boolean
          updated_at?: string
        }
        Update: {
          action_code?: string
          code?: string
          created_at?: string
          deprecated_at?: string | null
          description_key?: string | null
          id?: string
          label_key?: string
          module_code?: string
          required_entitlement_key?: string | null
          resource_code?: string
          scope?: Database["public"]["Enums"]["authorization_scope"]
          status?: string
          tenant_delegable?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      tenant_entitlements: {
        Row: {
          created_at: string
          created_by: string
          enabled: boolean
          module_key: string
          tenant_id: string
          updated_at: string
          version: number
        }
        Insert: {
          created_at?: string
          created_by: string
          enabled: boolean
          module_key: string
          tenant_id: string
          updated_at?: string
          version?: number
        }
        Update: {
          created_at?: string
          created_by?: string
          enabled?: boolean
          module_key?: string
          tenant_id?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "tenant_entitlements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_entitlements_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      tenant_invitations: {
        Row: {
          accepted_at: string | null
          created_at: string
          created_by: string
          expires_at: string
          id: string
          invite_ref: string
          invited_user_id: string | null
          recipient_email_hash: string
          revoked_at: string | null
          status: string
          target_profile_id: string | null
          tenant_id: string
          token_hash: string | null
          updated_at: string
          version: number
        }
        Insert: {
          accepted_at?: string | null
          created_at?: string
          created_by: string
          expires_at: string
          id?: string
          invite_ref?: string
          invited_user_id?: string | null
          recipient_email_hash: string
          revoked_at?: string | null
          status?: string
          target_profile_id?: string | null
          tenant_id: string
          token_hash?: string | null
          updated_at?: string
          version?: number
        }
        Update: {
          accepted_at?: string | null
          created_at?: string
          created_by?: string
          expires_at?: string
          id?: string
          invite_ref?: string
          invited_user_id?: string | null
          recipient_email_hash?: string
          revoked_at?: string | null
          status?: string
          target_profile_id?: string | null
          tenant_id?: string
          token_hash?: string | null
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "tenant_invitations_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_invitations_invited_user_id_fkey"
            columns: ["invited_user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_invitations_target_profile_fk"
            columns: ["tenant_id", "target_profile_id"]
            isOneToOne: false
            referencedRelation: "tenant_profiles"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "tenant_invitations_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
        ]
      }
      tenant_memberships: {
        Row: {
          blocked_at: string | null
          created_at: string
          created_by: string
          id: string
          joined_at: string
          profile_assigned_at: string | null
          profile_assigned_by: string | null
          profile_id: string | null
          revoked_at: string | null
          status: string
          tenant_id: string
          updated_at: string
          user_id: string
          version: number
        }
        Insert: {
          blocked_at?: string | null
          created_at?: string
          created_by: string
          id?: string
          joined_at: string
          profile_assigned_at?: string | null
          profile_assigned_by?: string | null
          profile_id?: string | null
          revoked_at?: string | null
          status: string
          tenant_id: string
          updated_at?: string
          user_id: string
          version?: number
        }
        Update: {
          blocked_at?: string | null
          created_at?: string
          created_by?: string
          id?: string
          joined_at?: string
          profile_assigned_at?: string | null
          profile_assigned_by?: string | null
          profile_id?: string | null
          revoked_at?: string | null
          status?: string
          tenant_id?: string
          updated_at?: string
          user_id?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "tenant_memberships_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_memberships_profile_assigned_by_fk"
            columns: ["profile_assigned_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_memberships_profile_fk"
            columns: ["tenant_id", "profile_id"]
            isOneToOne: false
            referencedRelation: "tenant_profiles"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "tenant_memberships_tenant_id_fkey"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_memberships_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      tenant_permission_overrides: {
        Row: {
          created_at: string
          created_by: string | null
          effect: string
          id: string
          membership_id: string
          permission_id: string
          tenant_id: string
          updated_at: string
          updated_by: string | null
          version: number
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          effect: string
          id?: string
          membership_id: string
          permission_id: string
          tenant_id: string
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Update: {
          created_at?: string
          created_by?: string | null
          effect?: string
          id?: string
          membership_id?: string
          permission_id?: string
          tenant_id?: string
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "tenant_permission_overrides_created_by_fk"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_permission_overrides_membership_fk"
            columns: ["tenant_id", "membership_id"]
            isOneToOne: false
            referencedRelation: "tenant_memberships"
            referencedColumns: ["tenant_id", "id"]
          },
          {
            foreignKeyName: "tenant_permission_overrides_permission_fk"
            columns: ["permission_id"]
            isOneToOne: false
            referencedRelation: "permission_catalog"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_permission_overrides_updated_by_fk"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      tenant_profile_permissions: {
        Row: {
          created_at: string
          created_by: string | null
          permission_id: string
          profile_id: string
          tenant_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          permission_id: string
          profile_id: string
          tenant_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          permission_id?: string
          profile_id?: string
          tenant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "tenant_profile_permissions_created_by_fk"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_profile_permissions_permission_fk"
            columns: ["permission_id"]
            isOneToOne: false
            referencedRelation: "permission_catalog"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_profile_permissions_profile_fk"
            columns: ["tenant_id", "profile_id"]
            isOneToOne: false
            referencedRelation: "tenant_profiles"
            referencedColumns: ["tenant_id", "id"]
          },
        ]
      }
      tenant_profiles: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          inactivated_at: string | null
          name: string
          status: string
          template_key: string | null
          template_version: number | null
          tenant_id: string
          updated_at: string
          updated_by: string | null
          version: number
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          inactivated_at?: string | null
          name: string
          status?: string
          template_key?: string | null
          template_version?: number | null
          tenant_id: string
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          inactivated_at?: string | null
          name?: string
          status?: string
          template_key?: string | null
          template_version?: number | null
          tenant_id?: string
          updated_at?: string
          updated_by?: string | null
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "tenant_profiles_created_by_fk"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_profiles_tenant_fk"
            columns: ["tenant_id"]
            isOneToOne: false
            referencedRelation: "tenants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "tenant_profiles_updated_by_fk"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
      tenants: {
        Row: {
          created_at: string
          created_by: string
          display_name: string
          id: string
          inactivated_at: string | null
          status: string
          suspended_at: string | null
          tenant_ref: string
          updated_at: string
          version: number
        }
        Insert: {
          created_at?: string
          created_by: string
          display_name: string
          id?: string
          inactivated_at?: string | null
          status: string
          suspended_at?: string | null
          tenant_ref?: string
          updated_at?: string
          version?: number
        }
        Update: {
          created_at?: string
          created_by?: string
          display_name?: string
          id?: string
          inactivated_at?: string | null
          status?: string
          suspended_at?: string | null
          tenant_ref?: string
          updated_at?: string
          version?: number
        }
        Relationships: [
          {
            foreignKeyName: "tenants_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "app_users"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_tenant_invitation: {
        Args: { correlation_id?: string; invitation_token: string }
        Returns: {
          membership_id: string
          tenant_ref: string
        }[]
      }
      assign_tenant_membership_profile: {
        Args: {
          command_reason: string
          correlation_id?: string
          expected_membership_version: number
          target_membership_id: string
          target_profile_id: string
        }
        Returns: {
          command_correlation_id: string
          membership_id: string
          membership_version: number
          profile_id: string
        }[]
      }
      bootstrap_initial_tenant: {
        Args: {
          bootstrap_user_id: string
          correlation_id?: string
          tenant_display_name: string
        }
        Returns: {
          tenant_id: string
          tenant_ref: string
        }[]
      }
      change_tenant_membership_status: {
        Args: {
          command_reason: string
          correlation_id?: string
          expected_membership_version: number
          target_membership_id: string
          target_status: string
        }
        Returns: {
          command_correlation_id: string
          membership_id: string
          membership_status: string
          membership_version: number
        }[]
      }
      change_tenant_profile_status: {
        Args: {
          command_reason: string
          correlation_id?: string
          expected_profile_version: number
          target_profile_id: string
          target_status: string
        }
        Returns: {
          command_correlation_id: string
          profile_id: string
          profile_status: string
          profile_version: number
        }[]
      }
      claim_outbox_batch: {
        Args: { batch_size?: number; worker_identity: string }
        Returns: {
          actor_kind: string
          actor_ref: string
          actor_user_id: string
          aggregate_id: string
          aggregate_type: string
          aggregate_version: number
          attempt_count: number
          causation_id: string
          claimed_by: string
          command_id: string
          consumer_name: string
          correlation_id: string
          event_id: string
          event_type: string
          event_version: number
          fencing_token: number
          handler_name: string
          handler_version: number
          lease_expires_at: string
          lease_token: string
          metadata: Json
          occurred_at: string
          payload: Json
          scope_kind: string
          source: string
          tenant_id: string
        }[]
      }
      complete_outbox_event: {
        Args: {
          current_fencing_token: number
          current_lease_token: string
          handler_result?: Json
          handler_result_version: number
          target_event_id: string
          worker_identity: string
        }
        Returns: {
          receipt_id: string
          receipt_replayed: boolean
        }[]
      }
      create_tenant_invitation: {
        Args: {
          correlation_id?: string
          invitation_expires_at: string
          operator_user_id: string
          recipient_email: string
          target_profile_id: string
          target_tenant_id: string
        }
        Returns: {
          invitation_token: string
          invite_ref: string
        }[]
      }
      create_tenant_profile:
        | {
            Args: {
              command_reason: string
              correlation_id?: string
              profile_name: string
            }
            Returns: {
              command_correlation_id: string
              profile_id: string
              profile_version: number
            }[]
          }
        | {
            Args: {
              command_idempotency_key: string
              command_reason: string
              correlation_id: string
              profile_name: string
            }
            Returns: {
              command_correlation_id: string
              profile_id: string
              profile_version: number
            }[]
          }
      delete_tenant_permission_override: {
        Args: {
          command_reason: string
          correlation_id?: string
          expected_membership_version: number
          expected_override_version: number
          target_override_id: string
        }
        Returns: {
          command_correlation_id: string
          deleted_override_id: string
          membership_version: number
        }[]
      }
      expire_tenant_invitation: {
        Args: {
          correlation_id?: string
          operator_user_id: string
          target_invite_ref: string
        }
        Returns: undefined
      }
      expire_tenant_invitation_authenticated: {
        Args: {
          command_reason: string
          correlation_id?: string
          expected_invitation_version: number
          target_invite_ref: string
        }
        Returns: {
          command_correlation_id: string
          invitation_status: string
          invitation_version: number
          invite_ref: string
        }[]
      }
      fail_outbox_event: {
        Args: {
          current_fencing_token: number
          current_lease_token: string
          failure_class: string
          failure_code: string
          failure_message: string
          target_event_id: string
          worker_identity: string
        }
        Returns: {
          applied_backoff_seconds: number
          delivery_status: string
          next_eligible_at: string
        }[]
      }
      invite_tenant_user: {
        Args: {
          command_reason: string
          correlation_id?: string
          expected_profile_version: number
          invitation_expires_at: string
          recipient_email: string
          target_profile_id: string
        }
        Returns: {
          command_correlation_id: string
          invitation_token: string
          invite_ref: string
        }[]
      }
      read_profile_created_origin: {
        Args: {
          current_fencing_token: number
          current_lease_token: string
          target_event_id: string
          worker_identity: string
        }
        Returns: {
          authoritative_profile_id: string
          authoritative_profile_status: string
          authoritative_profile_version: number
          authoritative_tenant_id: string
        }[]
      }
      resolve_my_authorization: {
        Args: never
        Returns: {
          authorization_revision: string
          catalog_revision: number
          enabled_entitlements: string[]
          membership_id: string
          membership_version: number
          permission_codes: string[]
          principal_id: string
          profile_id: string
          profile_name: string
          profile_version: number
          projection_status: string
          tenant_id: string
          tenant_ref: string
        }[]
      }
      resolve_my_tenant_context: {
        Args: { target_tenant_ref?: string }
        Returns: {
          context_status: string
          membership_id: string
          membership_version: number
          principal_id: string
          tenant_display_name: string
          tenant_id: string
          tenant_ref: string
        }[]
      }
      revoke_tenant_invitation: {
        Args: {
          correlation_id?: string
          operator_user_id: string
          target_invite_ref: string
        }
        Returns: undefined
      }
      revoke_tenant_invitation_authenticated: {
        Args: {
          command_reason: string
          correlation_id?: string
          expected_invitation_version: number
          target_invite_ref: string
        }
        Returns: {
          command_correlation_id: string
          invitation_status: string
          invitation_version: number
          invite_ref: string
        }[]
      }
      set_tenant_permission_override: {
        Args: {
          command_reason: string
          correlation_id?: string
          expected_membership_version: number
          expected_override_version?: number
          target_effect: string
          target_membership_id: string
          target_permission_id: string
        }
        Returns: {
          command_correlation_id: string
          membership_version: number
          override_id: string
          override_version: number
        }[]
      }
      set_tenant_profile_permission: {
        Args: {
          command_reason: string
          correlation_id?: string
          expected_profile_version: number
          target_allowed: boolean
          target_permission_id: string
          target_profile_id: string
        }
        Returns: {
          allowed: boolean
          command_correlation_id: string
          permission_id: string
          profile_id: string
          profile_version: number
        }[]
      }
      update_tenant_profile: {
        Args: {
          command_reason: string
          correlation_id?: string
          expected_profile_version: number
          profile_name: string
          target_profile_id: string
        }
        Returns: {
          command_correlation_id: string
          profile_id: string
          profile_version: number
        }[]
      }
    }
    Enums: {
      authorization_scope: "OWN" | "ASSIGNED" | "TEAM" | "ALL_TENANT"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      authorization_scope: ["OWN", "ASSIGNED", "TEAM", "ALL_TENANT"],
    },
  },
} as const
