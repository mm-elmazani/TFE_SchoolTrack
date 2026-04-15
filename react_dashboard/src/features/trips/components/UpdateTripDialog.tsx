import { useState, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { tripApi, type Trip } from '../api/tripApi';
import { classApi } from '@/features/classes/api/classApi';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { 
  Select, 
  SelectContent, 
  SelectItem, 
  SelectTrigger, 
  SelectValue 
} from '@/components/ui/select';
import { Loader2, MapPin, Calendar, AlignLeft, Activity, School, CheckSquare, Square } from 'lucide-react';
import { cn } from '@/lib/utils';

const tripSchema = z.object({
  destination: z.string().min(1, 'La destination est requise'),
  date: z.string().min(1, 'La date est requise'),
  description: z.string().optional().or(z.literal('')),
  status: z.enum(['PLANNED', 'ACTIVE', 'COMPLETED', 'ARCHIVED']),
  class_ids: z.array(z.string()).min(1, 'Au moins une classe est requise'),
});

type TripForm = z.infer<typeof tripSchema>;

interface UpdateTripDialogProps {
  trip: Trip | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function UpdateTripDialog({ trip, open, onOpenChange }: UpdateTripDialogProps) {
  const [serverError, setServerError] = useState<string | null>(null);
  const [hasInitialized, setHasInitialized] = useState(false);
  const [pendingCompleteData, setPendingCompleteData] = useState<TripForm | null>(null);
  const queryClient = useQueryClient();

  const { data: classes, isLoading: loadingClasses } = useQuery({
    queryKey: ['classes'],
    queryFn: classApi.getAll,
    enabled: open,
  });

  const { register, handleSubmit, formState: { errors }, reset, setValue, watch } = useForm<TripForm>({
    resolver: zodResolver(tripSchema),
  });

  // Initialize form once when dialog opens and classes are loaded
  useEffect(() => {
    if (trip && open && classes && !hasInitialized) {
      const tripClassNames = new Set(trip.classes?.map(c => c.name) || []);
      const matchedIds = classes.filter(c => tripClassNames.has(c.name)).map(c => c.id);
      reset({
        destination: trip.destination,
        date: trip.date,
        description: trip.description || '',
        status: trip.status,
        class_ids: matchedIds,
      });
      setHasInitialized(true);
    }
    if (!open) setHasInitialized(false);
  }, [trip, open, classes, hasInitialized, reset]);

  const currentStatus = watch('status');
  const selectedClassIds = watch('class_ids') || [];

  const toggleClass = (id: string) => {
    const current = [...selectedClassIds];
    if (current.includes(id)) {
      setValue('class_ids', current.filter(cid => cid !== id), { shouldValidate: true, shouldDirty: true });
    } else {
      setValue('class_ids', [...current, id], { shouldValidate: true, shouldDirty: true });
    }
  };

  const updateMutation = useMutation({
    mutationFn: (data: TripForm) => tripApi.update(trip!.id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['trips'] });
      queryClient.invalidateQueries({ queryKey: ['trips', trip?.id] });
      onOpenChange(false);
    },
    onError: (error: any) => {
      const detail = error.response?.data?.detail;
      if (Array.isArray(detail)) {
        setServerError(detail[0]?.msg || 'Erreur de validation');
      } else {
        setServerError(detail || 'Erreur lors de la modification');
      }
    }
  });

  const onSubmit = (data: TripForm) => {
    setServerError(null);
    // Demande de confirmation si on passe le voyage en "Terminé"
    if (data.status === 'COMPLETED' && trip?.status !== 'COMPLETED') {
      setPendingCompleteData(data);
      return;
    }
    updateMutation.mutate(data);
  };

  const confirmComplete = () => {
    if (pendingCompleteData) {
      updateMutation.mutate(pendingCompleteData);
      setPendingCompleteData(null);
    }
  };

  return (
    <>
    {/* Modale de confirmation — passage en "Terminé" */}
    <Dialog open={!!pendingCompleteData} onOpenChange={(val) => { if (!val) setPendingCompleteData(null); }}>
      <DialogContent className="sm:max-w-[420px] rounded-2xl overflow-hidden p-0 border-0 shadow-2xl">
        <div className="h-2 bg-amber-500 w-full" />
        <div className="p-6">
          <DialogHeader className="mb-4">
            <DialogTitle className="text-xl font-bold text-slate-900 font-heading flex items-center gap-2">
              <Activity className="w-5 h-5 text-amber-500" />
              Confirmer la clôture du voyage
            </DialogTitle>
            <DialogDescription className="text-slate-500 font-sans text-sm leading-relaxed">
              Vous êtes sur le point de marquer le voyage{' '}
              <span className="font-semibold text-slate-700">"{trip?.destination}"</span> comme{' '}
              <span className="font-semibold text-amber-600">Terminé</span>.
              <br /><br />
              Cette action indique que le voyage est achevé. Êtes-vous sûr de vouloir continuer ?
            </DialogDescription>
          </DialogHeader>
          <DialogFooter className="flex gap-3 pt-2">
            <Button
              type="button"
              variant="outline"
              onClick={() => setPendingCompleteData(null)}
              className="rounded-xl h-11 border-slate-200 flex-1 hover:bg-slate-50 font-sans"
            >
              Annuler
            </Button>
            <Button
              type="button"
              onClick={confirmComplete}
              disabled={updateMutation.isPending}
              className="rounded-xl h-11 bg-amber-500 hover:bg-amber-600 text-white flex-1 font-sans shadow-lg shadow-amber-500/20 transition-all active:scale-95"
            >
              {updateMutation.isPending ? (
                <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Mise à jour...</>
              ) : 'Oui, marquer comme terminé'}
            </Button>
          </DialogFooter>
        </div>
      </DialogContent>
    </Dialog>

    <Dialog open={open} onOpenChange={(val) => {
      setServerError(null);
      onOpenChange(val);
    }}>
      <DialogContent className="sm:max-w-[550px] rounded-2xl overflow-hidden p-0 border-0 shadow-2xl">
        <div className="h-2 bg-schooltrack-primary w-full" />
        <div className="p-6">
          <DialogHeader className="mb-6">
            <DialogTitle className="text-2xl font-bold text-schooltrack-primary font-heading">Modifier le voyage</DialogTitle>
            <DialogDescription className="text-slate-500 font-sans">
              Mettez à jour les informations et le statut de votre expédition.
            </DialogDescription>
          </DialogHeader>

          <form onSubmit={handleSubmit(onSubmit)} className="space-y-5">
            {serverError && (
              <div className="p-4 bg-red-50 text-schooltrack-error border border-red-100 rounded-xl text-sm animate-in fade-in zoom-in duration-200 font-sans">
                {serverError}
              </div>
            )}

            <div className="space-y-2">
              <Label htmlFor="destination_update" className="text-slate-700 font-bold flex items-center gap-2">
                <MapPin className="w-4 h-4 text-schooltrack-action" /> Destination
              </Label>
              <Input 
                id="destination_update" 
                {...register('destination')} 
                placeholder="ex: Rome, Italie"
                className={cn(
                  "rounded-xl border-slate-200 h-11 focus:ring-schooltrack-primary focus:border-schooltrack-primary font-sans",
                  errors.destination && "border-schooltrack-error bg-red-50/30"
                )} 
              />
              {errors.destination && <p className="text-schooltrack-error text-[10px] font-bold mt-1 uppercase tracking-tight">{errors.destination.message}</p>}
            </div>

            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="date_update" className="text-slate-700 font-bold flex items-center gap-2">
                  <Calendar className="w-4 h-4 text-schooltrack-action" /> Date
                </Label>
                <Input 
                  id="date_update" 
                  type="date" 
                  {...register('date')} 
                  className={cn(
                    "rounded-xl border-slate-200 h-11 focus:ring-schooltrack-primary focus:border-schooltrack-primary font-sans",
                    errors.date && "border-schooltrack-error bg-red-50/30"
                  )} 
                />
                {errors.date && <p className="text-schooltrack-error text-[10px] font-bold mt-1 uppercase tracking-tight">{errors.date.message}</p>}
              </div>

              <div className="space-y-2">
                <Label className="text-slate-700 font-bold flex items-center gap-2">
                  <Activity className="w-4 h-4 text-schooltrack-action" /> Statut
                </Label>
                <Select 
                  value={currentStatus} 
                  onValueChange={(val: any) => setValue('status', val, { shouldDirty: true })}
                >
                  <SelectTrigger className="rounded-xl border-slate-200 h-11 focus:ring-schooltrack-primary font-sans">
                    <SelectValue placeholder="Choisir un statut" />
                  </SelectTrigger>
                  <SelectContent className="rounded-xl border-slate-200 shadow-xl">
                    <SelectItem value="PLANNED">À venir (Planned)</SelectItem>
                    <SelectItem value="ACTIVE">En cours (Active)</SelectItem>
                    <SelectItem value="COMPLETED">Terminé (Completed)</SelectItem>
                    <SelectItem value="ARCHIVED">Archivé</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>

            <div className="space-y-2">
              <Label className="text-slate-700 font-bold flex items-center gap-2">
                <School className="w-4 h-4 text-schooltrack-action" /> Classes participantes
              </Label>
              <div className={cn(
                "border border-slate-200 rounded-2xl p-4 bg-slate-50/50 max-h-[150px] overflow-y-auto space-y-2",
                errors.class_ids && "border-schooltrack-error"
              )}>
                {loadingClasses ? (
                  <div className="flex items-center justify-center py-4">
                    <Loader2 className="w-5 h-5 animate-spin text-slate-400" />
                  </div>
                ) : (
                  classes?.map((cls) => (
                    <div 
                      key={cls.id} 
                      className={cn(
                        "flex items-center justify-between p-3 rounded-xl cursor-pointer transition-all border",
                        selectedClassIds.includes(cls.id) 
                          ? "bg-white border-schooltrack-primary shadow-sm" 
                          : "bg-transparent border-transparent hover:bg-white hover:border-slate-200"
                      )}
                      onClick={() => toggleClass(cls.id)}
                    >
                      <div className="flex items-center gap-3">
                        {selectedClassIds.includes(cls.id) 
                          ? <CheckSquare className="w-5 h-5 text-schooltrack-primary" /> 
                          : <Square className="w-5 h-5 text-slate-300" />
                        }
                        <span className={cn("text-sm font-medium", selectedClassIds.includes(cls.id) ? "text-slate-900" : "text-slate-600")}>
                          {cls.name}
                        </span>
                      </div>
                      <span className="text-[10px] text-slate-400 uppercase font-bold">{cls.year}</span>
                    </div>
                  ))
                )}
              </div>
              {errors.class_ids && <p className="text-schooltrack-error text-[10px] font-bold mt-1 uppercase tracking-tight">{errors.class_ids.message}</p>}
            </div>

            <div className="space-y-2">
              <Label htmlFor="description_update" className="text-slate-700 font-bold flex items-center gap-2">
                <AlignLeft className="w-4 h-4 text-schooltrack-action" /> Description
              </Label>
              <Textarea 
                id="description_update" 
                {...register('description')} 
                placeholder="Objectifs pédagogiques, itinéraire..."
                className="rounded-xl border-slate-200 min-h-[80px] focus:ring-schooltrack-primary focus:border-schooltrack-primary resize-none font-sans"
              />
            </div>

            <DialogFooter className="gap-3 pt-4 border-t border-slate-50 mt-6 flex-col">
              {Object.keys(errors).length > 0 && !serverError && (
                <p className="text-schooltrack-error text-xs font-bold text-center w-full animate-in fade-in duration-200">
                  Veuillez corriger les erreurs ci-dessus avant de sauvegarder.
                </p>
              )}
              <div className="flex gap-3 w-full">
                <Button
                  type="button"
                  variant="outline"
                  onClick={() => onOpenChange(false)}
                  className="rounded-xl h-11 border-slate-200 flex-1 hover:bg-slate-50 font-sans"
                >
                  Annuler
                </Button>
                <Button
                  type="submit"
                  disabled={updateMutation.isPending}
                  className="rounded-xl h-11 bg-schooltrack-primary hover:bg-blue-900 text-white px-8 flex-1 shadow-lg shadow-blue-900/20 transition-all active:scale-95 font-sans"
                >
                  {updateMutation.isPending ? (
                    <>
                      <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                      Mise à jour...
                    </>
                  ) : 'Sauvegarder les changements'}
                </Button>
              </div>
            </DialogFooter>
          </form>
        </div>
      </DialogContent>
    </Dialog>
    </>
  );
}

