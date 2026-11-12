/// Roles de SkonditBeats (los mismos que valida la API).
///   cliente     compra y abre tickets.
///   admin       administra catálogo, tickets y clientes.
///   superAdmin  todo lo del admin y además gestiona a los administradores.
enum Rol {
  superAdmin('SUPER_ADMIN', 'Super administrador'),
  admin('ADMIN', 'Administrador'),
  cliente('CLIENTE', 'Cliente');

  const Rol(this.api, this.etiqueta);
  final String api;
  final String etiqueta;

  static Rol desde(String? v) => Rol.values.where((r) => r.api == v).firstOrNull ?? Rol.cliente;

  bool get esAdmin => this == admin || this == superAdmin;
}

bool esRolAdmin(String? rol) => Rol.desde(rol).esAdmin;

/// ¿Quien tiene el rol [actor] puede modificar a una cuenta [objetivo] y
/// dejarla como [nuevo]? Un admin solo gestiona clientes. Misma regla que la API.
bool puedeGestionar(String? actor, String? objetivo, [String? nuevo]) {
  final a = Rol.desde(actor);
  if (a == Rol.superAdmin) return true;
  if (a != Rol.admin) return false;
  return !esRolAdmin(objetivo) && (nuevo == null || !esRolAdmin(nuevo));
}

/// Roles que [actor] puede asignar.
List<Rol> rolesAsignables(String? actor) =>
    Rol.desde(actor) == Rol.superAdmin ? Rol.values : const [Rol.cliente];
