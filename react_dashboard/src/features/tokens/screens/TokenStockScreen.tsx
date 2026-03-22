import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { tokenApi } from '../api/tokenApi';
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
import { 
  Loader2, 
  Package, 
  CheckCircle, 
  User, 
  AlertTriangle, 
  SearchX,
  RefreshCw,
  Trash2
  } from 'lucide-react';import { cn } from '@/lib/utils';
import { useAuthStore } from '@/features/auth/store/authStore';

export default function TokenStockScreen() {
  const { getIsAdmin } = useAuthStore();
  const isAdmin = getIsAdmin();
  const queryClient = useQueryClient();

  const [statusFilter, setStatusFilter] = useState<string>('');
  const [typeFilter, setTypeFilter] = useState<string>('');

  const { data: stats, isLoading: isLoadingStats } = useQuery({
    queryKey: ['tokenStats'],
    queryFn: tokenApi.getTokenStats,
  });

  const { data: tokens, isLoading: isLoadingTokens, isFetching, refetch } = useQuery({
    queryKey: ['tokens', statusFilter, typeFilter],
    queryFn: () => tokenApi.getAllTokens({ 
      status: statusFilter || undefined, 
      token_type: typeFilter || undefined 
    }),
  });

  const updateStatusMutation = useMutation({
    mutationFn: ({ id, status }: { id: string | number, status: string }) => 
      tokenApi.updateTokenStatus(id, status),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tokens'] });
      queryClient.invalidateQueries({ queryKey: ['tokenStats'] });
    }
  });

  const deleteTokenMutation = useMutation({
    mutationFn: (id: string | number) => tokenApi.deleteToken(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tokens'] });
      queryClient.invalidateQueries({ queryKey: ['tokenStats'] });
    }
  });

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'AVAILABLE': return <Badge className="bg-green-50 text-schooltrack-success border-green-100 shadow-none hover:bg-green-50">Disponible</Badge>;
      case 'ASSIGNED': return <Badge className="bg-orange-50 text-schooltrack-warning border-orange-100 shadow-none hover:bg-orange-50">Assigné</Badge>;
      case 'DAMAGED': return <Badge className="bg-red-50 text-schooltrack-error border-red-100 shadow-none hover:bg-red-50">Endommagé</Badge>;
      case 'LOST': return <Badge variant="secondary" className="bg-slate-100 text-slate-500 border-slate-200">Perdu</Badge>;
      default: return <Badge variant="outline">{status}</Badge>;
    }
  };

  const getTypeBadge = (type: string) => {
    switch (type) {
      case 'NFC_PHYSICAL': return <Badge variant="outline" className="bg-blue-50 text-blue-700 border-blue-100 text-[10px]">NFC Physique</Badge>;
      case 'QR_PHYSICAL': return <Badge variant="outline" className="bg-purple-50 text-purple-700 border-purple-100 text-[10px]">QR Physique</Badge>;
      default: return <Badge variant="outline" className="text-[10px]">{type}</Badge>;
    }
  };

  if (isLoadingStats && !stats) return (
    <div className="flex h-64 items-center justify-center">
      <Loader2 className="w-8 h-8 animate-spin text-slate-400" />
      <span className="ml-2 text-slate-500 font-medium font-sans">Chargement du stock...</span>
    </div>
  );

  return (
    <div className="space-y-6 animate-in fade-in duration-500">
      <div className="flex flex-col gap-1">
        <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary font-heading">Stock Bracelets</h2>
        <p className="text-slate-500 font-sans">Gérez l'inventaire physique de vos supports NFC et QR.</p>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-2 md:grid-cols-5 gap-4 font-sans">
        <Card className="border-slate-200 shadow-sm bg-white rounded-2xl overflow-hidden">
          <div className="h-1 bg-slate-400" />
          <CardContent className="p-4 flex flex-col items-center justify-center text-center gap-2">
            <div className="w-10 h-10 bg-slate-50 rounded-xl flex items-center justify-center text-slate-500">
              <Package className="w-5 h-5" />
            </div>
            <div>
              <p className="text-2xl font-black text-slate-900 font-heading">{stats?.total || 0}</p>
              <p className="text-[10px] text-slate-500 uppercase font-bold tracking-widest">Total</p>
            </div>
          </CardContent>
        </Card>
        <Card className="border-slate-200 shadow-sm bg-white rounded-2xl overflow-hidden">
          <div className="h-1 bg-schooltrack-success" />
          <CardContent className="p-4 flex flex-col items-center justify-center text-center gap-2">
            <div className="w-10 h-10 bg-green-50 rounded-xl flex items-center justify-center text-schooltrack-success">
              <CheckCircle className="w-5 h-5" />
            </div>
            <div>
              <p className="text-2xl font-black text-schooltrack-success font-heading">{stats?.available || 0}</p>
              <p className="text-[10px] text-slate-500 uppercase font-bold tracking-widest">Disponibles</p>
            </div>
          </CardContent>
        </Card>
        <Card className="border-slate-200 shadow-sm bg-white rounded-2xl overflow-hidden">
          <div className="h-1 bg-schooltrack-warning" />
          <CardContent className="p-4 flex flex-col items-center justify-center text-center gap-2">
            <div className="w-10 h-10 bg-orange-50 rounded-xl flex items-center justify-center text-schooltrack-warning">
              <User className="w-5 h-5" />
            </div>
            <div>
              <p className="text-2xl font-black text-schooltrack-warning font-heading">{stats?.assigned || 0}</p>
              <p className="text-[10px] text-slate-500 uppercase font-bold tracking-widest">Assignés</p>
            </div>
          </CardContent>
        </Card>
        <Card className="border-slate-200 shadow-sm bg-white rounded-2xl overflow-hidden">
          <div className="h-1 bg-schooltrack-error" />
          <CardContent className="p-4 flex flex-col items-center justify-center text-center gap-2">
            <div className="w-10 h-10 bg-red-50 rounded-xl flex items-center justify-center text-schooltrack-error">
              <AlertTriangle className="w-5 h-5" />
            </div>
            <div>
              <p className="text-2xl font-black text-schooltrack-error font-heading">{stats?.damaged || 0}</p>
              <p className="text-[10px] text-slate-500 uppercase font-bold tracking-widest">Endommagés</p>
            </div>
          </CardContent>
        </Card>
        <Card className="border-slate-200 shadow-sm bg-white rounded-2xl overflow-hidden">
          <div className="h-1 bg-slate-300" />
          <CardContent className="p-4 flex flex-col items-center justify-center text-center gap-2">
            <div className="w-10 h-10 bg-slate-100 rounded-xl flex items-center justify-center text-slate-400">
              <SearchX className="w-5 h-5" />
            </div>
            <div>
              <p className="text-2xl font-black text-slate-500 font-heading">{stats?.lost || 0}</p>
              <p className="text-[10px] text-slate-500 uppercase font-bold tracking-widest">Perdus</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Filters and Actions */}
      <div className="flex flex-col sm:flex-row gap-4 justify-between items-end">
        <div className="flex gap-4 w-full sm:w-auto">
          <div className="flex flex-col gap-1.5 flex-1 sm:w-48">
            <label className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Statut</label>
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value)}
              className="w-full h-10 px-3 bg-white border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-schooltrack-primary/20 focus:border-schooltrack-primary font-sans"
            >
              <option value="">Tous</option>
              <option value="AVAILABLE">Disponibles</option>
              <option value="ASSIGNED">Assignés</option>
              <option value="DAMAGED">Endommagés</option>
              <option value="LOST">Perdus</option>
            </select>
          </div>
          <div className="flex flex-col gap-1.5 flex-1 sm:w-48">
            <label className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Type</label>
            <select
              value={typeFilter}
              onChange={(e) => setTypeFilter(e.target.value)}
              className="w-full h-10 px-3 bg-white border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-schooltrack-primary/20 focus:border-schooltrack-primary font-sans"
            >
              <option value="">Tous</option>
              <option value="NFC_PHYSICAL">NFC Physique</option>
              <option value="QR_PHYSICAL">QR Physique</option>
            </select>
          </div>
        </div>
        
        <Button 
          variant="outline" 
          onClick={() => refetch()}
          disabled={isFetching}
          className="rounded-xl border-slate-200 gap-2 font-sans w-full sm:w-auto shrink-0"
        >
          <RefreshCw className={cn("w-4 h-4", isFetching && "animate-spin")} />
          <span>Rafraîchir</span>
        </Button>
      </div>

      {/* Table */}
      <Card className="border-slate-200 shadow-sm overflow-hidden bg-white rounded-2xl">
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <Table>
              <TableHeader className="bg-slate-50/50">
                <TableRow className="hover:bg-transparent border-b-slate-100">
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-6 font-heading">Token UID</TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-6 font-heading">Type</TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-6 font-heading">Statut</TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-6 font-heading">Créé le</TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-6 font-heading">Dernière Assignation</TableHead>
                  <TableHead className="text-right font-semibold text-schooltrack-primary py-4 px-6 font-heading">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {isLoadingTokens ? (
                  <TableRow>
                    <TableCell colSpan={6} className="h-32 text-center">
                      <Loader2 className="w-8 h-8 animate-spin mx-auto text-slate-300" />
                    </TableCell>
                  </TableRow>
                ) : !tokens || tokens.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={6} className="h-48 text-center text-slate-500 italic font-sans">
                      Aucun bracelet trouvé pour ces critères.
                    </TableCell>
                  </TableRow>
                ) : (
                  tokens.map((token: any) => (
                    <TableRow key={token.id} className="hover:bg-slate-50/50 transition-colors group font-sans">
                      <TableCell className="py-4 px-6">
                        <div className="flex flex-col">
                          <code className="text-[13px] font-bold text-slate-700 bg-slate-100 px-1.5 py-0.5 rounded w-fit">
                            {token.token_uid}
                          </code>
                          {token.hardware_uid && (
                            <span className="text-[10px] text-slate-400 font-mono mt-1">HW: {token.hardware_uid}</span>
                          )}
                        </div>
                      </TableCell>
                      <TableCell className="py-4 px-6">
                        {getTypeBadge(token.token_type)}
                      </TableCell>
                      <TableCell className="py-4 px-6">
                        {getStatusBadge(token.status)}
                      </TableCell>
                      <TableCell className="py-4 px-6 text-sm text-slate-600">
                        {new Date(token.created_at).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })}
                      </TableCell>
                      <TableCell className="py-4 px-6 text-sm text-slate-600">
                        {token.last_assigned_at 
                          ? new Date(token.last_assigned_at).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })
                          : <span className="italic text-slate-400">—</span>}
                      </TableCell>
                      <TableCell className="text-right py-4 px-6">
                        {isAdmin && token.status !== 'ASSIGNED' ? (
                          <div className="flex items-center justify-end gap-2 opacity-0 group-hover:opacity-100 transition-opacity">
                            {/* Action select for quick status change */}
                            <select
                              className="h-8 px-2 text-[11px] font-medium bg-white border border-slate-200 rounded-lg text-slate-600 hover:border-slate-300 focus:outline-none focus:ring-2 focus:ring-schooltrack-primary/20 uppercase tracking-wider"
                              value=""
                              onChange={(e) => {
                                if(e.target.value) {
                                  updateStatusMutation.mutate({ id: token.id, status: e.target.value });
                                }
                              }}
                              disabled={updateStatusMutation.isPending}
                            >
                              <option value="" disabled>Changer statut...</option>
                              {token.status !== 'AVAILABLE' && <option value="AVAILABLE">Mettre Disponible</option>}
                              {token.status !== 'DAMAGED' && <option value="DAMAGED">Mettre Endommagé</option>}
                              {token.status !== 'LOST' && <option value="LOST">Mettre Perdu</option>}
                            </select>

                            <Button 
                              variant="ghost" 
                              size="icon" 
                              className="h-8 w-8 text-slate-400 hover:text-schooltrack-error hover:bg-red-50 rounded-lg shrink-0"
                              onClick={() => {
                                if(confirm(`Supprimer définitivement le bracelet ${token.token_uid} ?`)) {
                                  deleteTokenMutation.mutate(token.id);
                                }
                              }}
                              disabled={deleteTokenMutation.isPending}
                            >
                              <Trash2 className="w-4 h-4" />
                            </Button>
                          </div>
                        ) : (
                          <span className="text-[10px] text-slate-300 italic px-2">Non modifiable</span>
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
    </div>
  );
}
