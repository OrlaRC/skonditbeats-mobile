/// Usuario autenticado, tal como lo devuelve la API.
class User {
  const User({
    required this.id,
    required this.email,
    required this.nombre,
    required this.rol,
    this.username,
    this.fotoUrl,
  });

  final String id;
  final String email;
  final String nombre;
  final String rol;
  final String? username;
  final String? fotoUrl;

  /// ADMIN o SUPER_ADMIN: acceso al panel de administración.
  bool get isAdmin => rol == 'ADMIN' || rol == 'SUPER_ADMIN';

  bool get isSuperAdmin => rol == 'SUPER_ADMIN';

  User copyWith({String? nombre, String? fotoUrl}) => User(
        id: id,
        email: email,
        nombre: nombre ?? this.nombre,
        rol: rol,
        username: username,
        fotoUrl: fotoUrl ?? this.fotoUrl,
      );

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: json['id'] as String,
        email: json['email'] as String,
        nombre: (json['nombre'] as String?) ?? '',
        rol: (json['rol'] as String?) ?? 'CLIENTE',
        username: json['username'] as String?,
        fotoUrl: json['foto_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'nombre': nombre,
        'rol': rol,
        'username': username,
        'foto_url': fotoUrl,
      };
}
