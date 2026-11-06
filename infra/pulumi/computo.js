const aws = require('@pulumi/aws');
const pulumi = require('@pulumi/pulumi');
const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

function crearComputo(red, { bucket, region }, opciones) {
  const rutaPaquete = join(__dirname, '.asistencia', 'app.tar.gz');
  const huella = createHash('sha256').update(readFileSync(rutaPaquete)).digest('hex');
  const plantilla = readFileSync(join(__dirname, '..', 'cloud-init.yaml'), 'utf8')
    .replaceAll('__REGION_APP__', region);

  const paquete = new aws.s3.BucketObjectv2('app', {
    bucket,
    key: `cloud-init-2/pulumi/app/${huella}.tar.gz`,
    source: new pulumi.asset.FileAsset(rutaPaquete),
    contentType: 'application/gzip',
    serverSideEncryption: 'AES256',
  }, opciones);

  const rolDescarga = new aws.iam.Role('descarga', {
    namePrefix: 'asistencia-descarga-',
    assumeRolePolicy: JSON.stringify({
      Version: '2012-10-17',
      Statement: [{
        Effect: 'Allow',
        Action: 'sts:AssumeRole',
        Principal: { Service: 'ec2.amazonaws.com' },
      }],
    }),
  }, opciones);

  const permiso = new aws.iam.RolePolicy('descarga', {
    name: 'descarga-paquete',
    role: rolDescarga.name,
    policy: paquete.arn.apply((arn) => JSON.stringify({
      Version: '2012-10-17',
      Statement: [{ Effect: 'Allow', Action: 's3:GetObject', Resource: arn }],
    })),
  }, opciones);

  const perfil = new aws.iam.InstanceProfile('descarga', {
    namePrefix: 'asistencia-descarga-',
    role: rolDescarga.name,
  }, opciones);

  const ami = aws.ssm.getParameterOutput({
    name: '/aws/service/canonical/ubuntu/server/noble/stable/current/amd64/hvm/ebs-gp3/ami-id',
  }, opciones).value;

  const llave = aws.ec2.getKeyPairOutput({ keyName: 'globomatics' }, opciones).keyName;
  const urlPaquete = pulumi.interpolate`s3://${paquete.bucket}/${paquete.key}`;

  function userData(rol, url, origenCliente) {
    return plantilla
      .replaceAll('__ROL__', rol)
      .replaceAll('__ORIGEN_CLIENTE__', origenCliente)
      .replaceAll('__URL_APP__', url);
  }

  const opcionesInstancia = {
    ...opciones,
    dependsOn: [red.asociacion, ...red.salidas, permiso],
    deleteBeforeReplace: true,
  };
  const comun = {
    ami,
    subnetId: red.subred.id,
    associatePublicIpAddress: true,
    keyName: llave,
    iamInstanceProfile: perfil.name,
    userDataReplaceOnChange: true,
    creditSpecification: { cpuCredits: 'standard' },
    metadataOptions: { httpTokens: 'required' },
    rootBlockDevice: { encrypted: true },
  };

  const cliente = new aws.ec2.Instance('cliente', {
    ...comun,
    instanceType: 't3.micro',
    privateIp: '10.42.1.10',
    vpcSecurityGroupIds: [red.grupos.cliente.id],
    userData: urlPaquete.apply((url) => userData('cliente', url, '__ORIGEN_CLIENTE__')),
    tags: { Name: 'asistencia-cliente' },
  }, opcionesInstancia);

  const backend = new aws.ec2.Instance('backend', {
    ...comun,
    instanceType: 't3.small',
    privateIp: '10.42.1.20',
    vpcSecurityGroupIds: [red.grupos.backend.id],
    userData: pulumi.all([urlPaquete, cliente.publicIp])
      .apply(([url, ip]) => userData('backend', url, `http://${ip}`)),
    tags: { Name: 'asistencia-backend' },
  }, opcionesInstancia);

  return { cliente, backend };
}

module.exports = { crearComputo };
