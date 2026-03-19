

def create_api_response(event, http_status_code, result):
    """Create a standardized API response"""
    response_body = {
        'application/json': {
            'body': result if http_status_code == 200 else {
                'error': result.get('error', 'UNKNOWN_ERROR'),
                'message': result.get('message', 'Query execution failed'),
                'hint': result.get('hint', 'Please review and modify your query')
            }
        }
    }

    action_response = {
        'actionGroup': event['actionGroup'],
        'apiPath': event['apiPath'],
        'httpMethod': event['httpMethod'],
        'httpStatusCode': http_status_code,
        'responseBody': response_body
    }

    return {'messageVersion': '1.0', 'response': action_response}

def get_property_value(properties, prop_name, error_code, example_type, event):
    """
    Helper function to extract property value from request properties with error handling

    Args:
        properties (list): List of property dictionaries from the request
        prop_name (str): Name of the property to extract
        error_code (str): Error code to use if property is missing
        example_type (str): Type of example to include in error response
        event (dict): Original event object for creating response

    Returns:
        str: Property value if found
        dict: Error response if property is missing or invalid
    """
    prop = next((p for p in properties if p.get('name') == prop_name), None)
    if prop is None or 'value' not in prop:
        return create_api_response(
            event,
            400,
            get_error_response(error_code, example_type=example_type)
        )
    return prop['value']

ERROR_MESSAGES = {
    'MISSING_PROPERTIES': {
        'message': 'No properties provided in the request',
        'hint': 'Please provide the required parameters based on the API endpoint'
    },
    'MISSING_QUERY': {
        'message': 'Query is required',
        'hint': 'No query was provided. Please provide a SQL query to execute'
    },
    'MISSING_DATABASE_NAME': {
        'message': 'Database name is required',
        'hint': 'Please provide the database name using the "database" parameter'
    },
    'MISSING_TABLE_NAME': {
        'message': 'Table name is required',
        'hint': 'Please provide the table name using the "table" parameter.'
    },
    'QUERY_EXECUTION_FAILED': {
        'message': 'Failed to execute query',
        'hint': 'Please use fully qualified table names.'
    },
    'QUERY_RESULT_ERROR': {
        'message': 'Error occurred while getting query results',
        'hint': 'Check if the tables and columns in your query exist and you have proper permissions.'
    },
    'INVALID_API_PATH_SCHEMA': {
        'message': 'Unknown API path',
        'hint': 'Available endpoints are: /postgress_query.'
    },
    'INVALID_API_PATH_QUERY': {
        'message': 'Unknown API path',
        'hint': 'Available endpoint is: /postgress_query'
    },
    'INTERNAL_ERROR': {
        'message': 'An unexpected error occurred',
        'hint': 'Please try again'
    },
}



def get_error_response(error_code, example_type=None, **kwargs):
    """
    Get formatted error response with optional dynamic content and specific example
    """
    error_info = ERROR_MESSAGES.get(error_code, ERROR_MESSAGES['INTERNAL_ERROR']).copy()

    if 'message' in kwargs:
        error_info['message'] = error_info['message'] + f": {kwargs['message']}"

    response = {
        'error': error_code,
        **error_info
    }


    return response