def get_tenant_context(user_id):

    # DUMMY LOGIC: In the future, this might query a DB for user-specific rules.
    def assign_user_to_group(user_id):
        # Simple dummy lookup for demo purposes
        groups = ["Group A", "Group B", "Group C"]
        return groups[hash(user_id) % len(groups)]
        
    assignment_group = assign_user_to_group(user_id)
    """
    In Tenant Isolation Mode, this environment is private to this user_id.
    You can safely perform user-specific lookups here.
    """
    # DUMMY LOGIC: In the future, this might query a DB for user-specific rules.
    test_string = f"\n<tenant_rules>User {user_id} belongs to {assignment_group}.</tenant_rules>"
    print(f"DEBUG: Tenant Context for user_id {user_id}: {test_string}")
    return test_string