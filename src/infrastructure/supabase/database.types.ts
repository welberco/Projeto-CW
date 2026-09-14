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
          actor_user_id: string | null
          correlation_id: string
          entity_id: string | null
          entity_type: string
          event_type: string
          id: string
          metadata: Json
          occurred_at: string
          tenant_id: string | null
        }
        Insert: {
          actor_kind: string
          actor_user_id?: string | null
          correlation_id?: string
          entity_id?: string | null
          entity_type: string
          event_type: string
          id?: string
          metadata?: Json
          occurred_at?: string
          tenant_id?: string | null
        }
        Update: {
          actor_kind?: string
          actor_user_id?: string | null
          correlation_id?: string
          entity_id?: string | null
          entity_type?: string
          event_type?: string
          id?: string
          metadata?: Json
          occurred_at?: string
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
      create_tenant_invitation: {
        Args: {
          correlation_id?: string
          invitation_expires_at: string
          operator_user_id: string
          recipient_email: string
          target_tenant_id: string
        }
        Returns: {
          invitation_token: string
          invite_ref: string
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
