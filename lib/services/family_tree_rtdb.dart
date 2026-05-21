import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class FamilyTreeRtdb {
  FamilyTreeRtdb({FirebaseDatabase? db})
      : _db = db ??
            FirebaseDatabase.instanceFor(
              app: FirebaseDatabase.instance.app,
              databaseURL:
                  'https://camello-family-tree-default-rtdb.asia-southeast1.firebasedatabase.app',
            );

  final FirebaseDatabase _db;

  String get _uid {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw Exception('Not signed in');
    return uid;
  }

  DatabaseReference treeRef(String treeId) => _db.ref('trees/$treeId');
  DatabaseReference metaRef(String treeId) => treeRef(treeId).child('meta');
  DatabaseReference membersRef(String treeId) => metaRef(treeId).child('members');
  DatabaseReference nodesRef(String treeId) => treeRef(treeId).child('nodes');

  Future<void> ensureMember(String treeId, {String roleIfMissing = 'editor'}) async {
    final myMemberRef = membersRef(treeId).child(_uid);
    final snap = await myMemberRef.get();
    if (snap.exists) return;

    await myMemberRef.set(roleIfMissing);

    // First user to create/join becomes admin.
    final createdByRef = metaRef(treeId).child('createdBy');
    final createdBySnap = await createdByRef.get();
    if (!createdBySnap.exists) {
      await createdByRef.set(_uid);
      await myMemberRef.set('admin');
    }
  }
  Future<void> saveMyChanges(
    String treeId, {
    required Map<int, Map<String, dynamic>> upsertsById,
    required Set<int> deletesById,
  }) async {
    await ensureMember(treeId);

    final updates = <String, dynamic>{};

    for (final e in upsertsById.entries) {
      final id = e.key;
      final map = e.value;
      for (final kv in map.entries) {
        updates['nodes/$id/${kv.key}'] = kv.value;
      }
    }

    for (final id in deletesById) {
      updates['nodes/$id'] = null;
    }

    updates['meta/updatedAt'] = ServerValue.timestamp;

    if (updates.isEmpty) return;

    await treeRef(treeId).update(updates);

    // Ensure createdBy exists (useful for auditing/ownership bootstrapping)
    final createdBySnap = await metaRef(treeId).child('createdBy').get();
    if (!createdBySnap.exists) {
      await metaRef(treeId).child('createdBy').set(_uid);
    }
  }

  Future<Map<dynamic, dynamic>?> loadTree(String treeId) async {
    // Only register membership when signed in.
    // Unauthenticated visitors can still read if Firebase rules allow it.
    if (FirebaseAuth.instance.currentUser != null) {
      await ensureMember(treeId);
    }

    final snap = await treeRef(treeId).get();
    if (!snap.exists) return null;

    final v = snap.value;
    if (v is Map) return Map<dynamic, dynamic>.from(v);
    return null;
  }
}