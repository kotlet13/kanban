/// Online observations may be reused only inside the same bounded logical
/// operation. Offline knowledge never promotes itself to an online observation.
bool canReuseCryptoReadAuthority({required Duration age,required bool identityCurrent,required bool lifecycleMatches,required bool pinsMatch,required bool onlineVerified,required bool active})=>active && onlineVerified && identityCurrent && lifecycleMatches && pinsMatch && age>=Duration.zero && age<const Duration(seconds:5);
