const pulumi = require('@pulumi/pulumi');
const aws = require('@pulumi/aws');
const { crearRed } = require('./red');
const { crearComputo } = require('./computo');

const config = new pulumi.Config();
const region = config.require('region');
const bucket = config.require('bucket');
const cuenta = config.require('cuenta');
const sshCidr = config.require('sshCidr');

const proveedor = new aws.Provider('asistencia', {
  region,
  allowedAccountIds: [cuenta],
});
const opciones = { provider: proveedor };

const red = crearRed(sshCidr, opciones);
const { cliente, backend } = crearComputo(red, { bucket, region }, opciones);

exports.ip_cliente = cliente.publicIp;
exports.ip_backend = backend.publicIp;
exports.url_cliente = pulumi.interpolate`http://${cliente.publicIp}`;
