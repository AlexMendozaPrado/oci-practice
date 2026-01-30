/*
## MyToDoReact version 1.0.
##
## Copyright (c) 2021 Oracle, Inc.
## Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl/
*/
/*
 * The swagger definition of the APIs can be found here:
 * https://objectstorage.eu-frankfurt-1.oraclecloud.com/n/oracleonpremjava/b/todolist/o/swagger_APIs_definition.json
 *
 * You can view it in swagger-ui by going to the following petstore swagger ui page and
 * pasting the URL above that points to the definitions of the APIs that are used in this app:
 * https://petstore.swagger.io/
 * @author  jean.de.lavarene@oracle.com
 */
// const API_LIST = 'http://localhost:8080/todolist';
// Copy from the endpoint from the API Gateway Deployment
// Example: const API_LIST = 'https://di2eyonlz5s7kmuektcddaw5zq.apigateway.<region>.oci.customer-oci.com/todolist';
// Set this to your Compute instance public IP before building the Docker image
// Example: const API_LIST = 'http://<YOUR_INSTANCE_PUBLIC_IP>:8080/todolist';
const API_LIST = process.env.REACT_APP_API_URL || 'http://localhost:8080/todolist';

export default API_LIST;
