import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { userApi } from '../api/userApi';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { 
  Table, 
  TableBody, 
  TableCell, 
  TableHead, 
  TableHeader, 
  TableRow 
} from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { useAuthStore } from '@/features/auth/store/authStore';
import { UserPlus, Mail, Trash2, Loader2, UserCog } from 'lucide-react';
import { cn } from '@/lib/utils';
import { CreateUserDialog } from '../components/CreateUserDialog';

export default function UserListScreen() {
  const { getIsAdmin, user: currentUser } = useAuthStore();
  const isAdmin = getIsAdmin();
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const queryClient = useQueryClient();

  const { data: users, isLoading, error } = useQuery({
    queryKey: ['users'],
    queryFn: userApi.getAll,
  });

  const deleteMutation = useMutation({
    mutationFn: (id: string) => userApi.delete(id),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['users'] }); },
  });

  const handleDelete = (user: { id: string; first_name: string | null; last_name: string | null }) => {
    if (!confirm(`Supprimer l'utilisateur ${user.first_name ?? ""} ${user.last_name ?? ""} ? Cette action est irréversible.`)) return;
    deleteMutation.mutate(user.id);
  };

  if (isLoading) return (
    <div className="flex h-64 items-center justify-center">
      <Loader2 className="w-8 h-8 animate-spin text-slate-400" />
      <span className="ml-2 text-slate-500 font-medium font-sans">Chargement des utilisateurs...</span>
    </div>
  );

  if (error) return (
    <div className="p-8 bg-red-50 text-schooltrack-error rounded-2xl border border-red-100 flex flex-col items-center gap-4 text-center font-sans">
      <div className="w-12 h-12 bg-red-100 rounded-full flex items-center justify-center">
        <UserCog className="w-6 h-6 text-schooltrack-error" />
      </div>
      <div>
        <h3 className="text-lg font-bold font-heading text-schooltrack-primary">Erreur de chargement</h3>
        <p className="text-sm opacity-80">Impossible de récupérer la liste des utilisateurs.</p>
      </div>
      <Button variant="outline" onClick={() => window.location.reload()}>Réessayer</Button>
    </div>
  );

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex flex-col gap-1">
          <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary font-heading">Utilisateurs</h2>
          <p className="text-slate-500 font-sans">Gérez les professeurs et les administrateurs de la plateforme.</p>
        </div>
        {isAdmin && (
          <Button 
            onClick={() => setIsCreateOpen(true)}
            className="bg-schooltrack-action hover:bg-blue-700 text-white rounded-xl h-11 px-6 shadow-md shadow-blue-900/10 flex items-center gap-2 transition-all active:scale-95 border-0 font-sans"
          >
            <UserPlus className="w-4 h-4" />
            <span>Nouvel Utilisateur</span>
          </Button>
        )}
      </div>

      <Card className="border-slate-200 shadow-sm overflow-hidden bg-white rounded-2xl">
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <Table>
              <TableHeader className="bg-slate-50/50">
                <TableRow className="hover:bg-transparent border-b-slate-100">
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-6 font-heading">Utilisateur</TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-6 font-heading">Email</TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-6 font-heading">Rôle</TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-6 text-center font-heading">2FA</TableHead>
                  <TableHead className="text-right font-semibold text-schooltrack-primary py-4 px-6 font-heading">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {users?.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={5} className="h-48 text-center text-slate-500 italic font-sans">
                      Aucun utilisateur trouvé
                    </TableCell>
                  </TableRow>
                ) : (
                  users?.map((u) => (
                    <TableRow key={u.id} className="hover:bg-slate-50/50 transition-colors group">
                      <TableCell className="font-medium py-4 px-6">
                        <div className="flex items-center gap-3">
                          <div className="w-9 h-9 bg-slate-100 rounded-full flex items-center justify-center text-schooltrack-primary font-bold text-xs group-hover:bg-white group-hover:shadow-sm transition-all">
                            {u.first_name?.[0]}{u.last_name?.[0]}
                          </div>
                          <div className="flex flex-col font-sans">
                            <span className="text-slate-900 font-bold">{u.first_name} {u.last_name}</span>
                            <span className="text-[10px] text-slate-400 font-mono tracking-tighter">#{u.id.substring(0,8)}</span>
                          </div>
                        </div>
                      </TableCell>
                      <TableCell className="py-4 px-6">
                        <div className="flex items-center gap-2 text-slate-600 font-sans">
                          <Mail className="w-3.5 h-3.5 opacity-40" />
                          <span className="text-sm">{u.email}</span>
                        </div>
                      </TableCell>
                      <TableCell className="py-4 px-6">
                        <Badge variant={u.role === 'DIRECTION' || u.role === 'ADMIN_TECH' ? 'default' : 'secondary'} className={cn(
                          "uppercase text-[10px] tracking-wider font-semibold font-sans",
                          u.role === 'DIRECTION' || u.role === 'ADMIN_TECH' ? "bg-schooltrack-primary text-white" : "bg-slate-100 text-slate-600 hover:bg-slate-100"
                        )}>
                          {u.role}
                        </Badge>
                      </TableCell>
                      <TableCell className="text-center py-4 px-6">
                        {u.is_2fa_enabled ? (
                          <Badge className="bg-green-50 text-schooltrack-success border-green-100 hover:bg-green-50 shadow-none text-[10px] font-sans">Activé</Badge>
                        ) : (
                          <Badge variant="outline" className="text-slate-400 border-slate-200 text-[10px] font-sans">Inactif</Badge>
                        )}
                      </TableCell>
                      <TableCell className="text-right py-4 px-6">
                        {isAdmin && u.id !== currentUser?.id ? (
                          <Button
                            variant="ghost"
                            size="sm"
                            className="h-9 w-9 p-0 text-red-500 hover:text-red-600 hover:bg-red-50 rounded-lg"
                            disabled={deleteMutation.isPending}
                            onClick={() => handleDelete(u)}
                          >
                            {deleteMutation.isPending && deleteMutation.variables === u.id
                              ? <Loader2 className="w-4 h-4 animate-spin" />
                              : <Trash2 className="w-4 h-4" />}
                          </Button>
                        ) : (
                          <span className="text-[10px] text-slate-300 italic px-2 font-sans">Action restreinte</span>
                        )}
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      <CreateUserDialog open={isCreateOpen} onOpenChange={setIsCreateOpen} />
    </div>
  );
}
