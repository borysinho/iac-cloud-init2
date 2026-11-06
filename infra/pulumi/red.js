const aws = require('@pulumi/aws');

function crearRed(sshCidr, opciones) {
  const vpc = new aws.ec2.Vpc('asistencia', {
    cidrBlock: '10.42.0.0/16',
    enableDnsSupport: true,
    enableDnsHostnames: true,
    tags: { Name: 'asistencia' },
  }, opciones);

  const subred = new aws.ec2.Subnet('publica', {
    vpcId: vpc.id,
    cidrBlock: '10.42.1.0/24',
    tags: { Name: 'asistencia-publica' },
  }, opciones);

  const internet = new aws.ec2.InternetGateway('asistencia', {
    vpcId: vpc.id,
    tags: { Name: 'asistencia' },
  }, opciones);

  const tabla = new aws.ec2.RouteTable('publica', {
    vpcId: vpc.id,
    routes: [{ cidrBlock: '0.0.0.0/0', gatewayId: internet.id }],
    tags: { Name: 'asistencia-publica' },
  }, opciones);

  const asociacion = new aws.ec2.RouteTableAssociation('publica', {
    subnetId: subred.id,
    routeTableId: tabla.id,
  }, opciones);

  const grupos = {};
  const salidas = [];
  for (const rol of ['cliente', 'backend']) {
    const grupo = new aws.ec2.SecurityGroup(rol, {
      name: `asistencia-${rol}`,
      description: `Acceso de red para el rol ${rol}`,
      vpcId: vpc.id,
    }, opciones);

    grupos[rol] = grupo;

    new aws.vpc.SecurityGroupIngressRule(`ssh-${rol}`, {
      securityGroupId: grupo.id,
      ipProtocol: 'tcp',
      fromPort: 22,
      toPort: 22,
      cidrIpv4: sshCidr,
    }, opciones);

    salidas.push(new aws.vpc.SecurityGroupEgressRule(`salida-${rol}`, {
      securityGroupId: grupo.id,
      ipProtocol: '-1',
      cidrIpv4: '0.0.0.0/0',
    }, opciones));
  }

  new aws.vpc.SecurityGroupIngressRule('http', {
    securityGroupId: grupos.cliente.id,
    ipProtocol: 'tcp',
    fromPort: 80,
    toPort: 80,
    cidrIpv4: '0.0.0.0/0',
  }, opciones);

  new aws.vpc.SecurityGroupIngressRule('api', {
    securityGroupId: grupos.backend.id,
    referencedSecurityGroupId: grupos.cliente.id,
    ipProtocol: 'tcp',
    fromPort: 8090,
    toPort: 8090,
  }, opciones);

  return { subred, grupos, asociacion, salidas };
}

module.exports = { crearRed };
