import { useState, useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { tokenApi, type TripStudentInfo } from '../api/tokenApi';
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
import { Loader2, Rss, QrCode, AlignLeft } from 'lucide-react';

const assignSchema = z.object({
  token_uid: z.string().min(1, 'L\'UID du token est requis'),
  assignment_type: z.enum(['NFC_PHYSICAL', 'QR_PHYSICAL', 'QR_DIGITAL']),
  justification: z.string().optional(),
});

type AssignForm = z.infer<typeof assignSchema>;

interface AssignTokenDialogProps {
  student: TripStudentInfo | null;
  tripId: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  isReassign?: boolean;
}

export function AssignTokenDialog({ student, tripId, open, onOpenChange, isReassign }: AssignTokenDialogProps) {
  const [serverError, setServerError] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const { register, handleSubmit, formState: { errors }, reset, setValue, watch } = useForm<AssignForm>({
    resolver: zodResolver(assignSchema),
    defaultValues: {
      token_uid: '',
      assignment_type: 'NFC_PHYSICAL',
      justification: '',
    }
  });

  const assignmentType = watch('assignment_type');
  const isPhysical = assignmentType === 'NFC_PHYSICAL' || assignmentType === 'QR_PHYSICAL';

  // Fetch available physical tokens when NFC or QR physical is selected
  const { data: availableTokens, isLoading: isLoadingTokens } = useQuery({
    queryKey: ['tokens', 'available', assignmentType],
    queryFn: () => tokenApi.getAllTokens({ status: 'AVAILABLE', token_type: assignmentType }),
    enabled: open && isPhysical,
  });

  useEffect(() => {
    if (open) {
      reset({
        token_uid: student?.token_uid || '',
        assignment_type: student?.assignment_type || 'NFC_PHYSICAL',
        justification: '',
      });
    }
  }, [open, student, reset]);

  const mutation = useMutation({
    mutationFn: (data: AssignForm) => {
      const payload = {
        ...data,
        trip_id: tripId!,
        student_id: student!.id,
      };
      return isReassign ? tokenApi.reassignToken(payload) : tokenApi.assignToken(payload);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tokens', 'students', tripId] });
      queryClient.invalidateQueries({ queryKey: ['tokens', 'status', tripId] });
      onOpenChange(false);
      reset();
    },
    onError: (error: any) => {
      const detail = error.response?.data?.detail;
      if (Array.isArray(detail)) {
        setServerError(detail[0]?.msg || 'Erreur de validation');
      } else {
        setServerError(detail || 'Une erreur est survenue');
      }
    }
  });

  const onSubmit = (data: AssignForm) => {
    setServerError(null);
    mutation.mutate(data);
  };

  return (
    <Dialog open={open} onOpenChange={(val) => {
      if (!val) reset();
      setServerError(null);
      onOpenChange(val);
    }}>
      <DialogContent className="sm:max-w-[425px] rounded-2xl font-sans border-0 shadow-2xl overflow-hidden p-6">
        <DialogHeader className="mb-6">
          <DialogTitle className="text-2xl font-bold text-schooltrack-primary font-heading">
            {isReassign ? 'Réassigner un bracelet' : 'Assigner un bracelet'}
          </DialogTitle>
          <DialogDescription className="font-sans">
            Élève : <span className="font-bold text-slate-900">{student?.first_name} {student?.last_name}</span>
          </DialogDescription>
        </DialogHeader>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-5">
          {serverError && (
            <div className="p-4 bg-red-50 text-schooltrack-error border border-red-100 rounded-xl text-sm font-sans animate-in fade-in zoom-in duration-200">
              {serverError}
            </div>
          )}

          <div className="space-y-2">
            <Label htmlFor="assignment_type" className="text-slate-700 font-bold">Type de support</Label>
            <Select 
              value={assignmentType} 
              onValueChange={(val: any) => setValue('assignment_type', val)}
            >
              <SelectTrigger className="rounded-xl border-slate-200 h-11 font-sans">
                <SelectValue placeholder="Choisir un type" />
              </SelectTrigger>
              <SelectContent className="rounded-xl border-slate-200 shadow-xl">
                <SelectItem value="NFC_PHYSICAL" className="font-sans">
                  <div className="flex items-center gap-2">
                    <Rss className="w-4 h-4 text-blue-600" />
                    <span>NFC Physique (Bracelet)</span>
                  </div>
                </SelectItem>
                <SelectItem value="QR_PHYSICAL" className="font-sans">
                  <div className="flex items-center gap-2">
                    <QrCode className="w-4 h-4 text-purple-600" />
                    <span>QR Physique (Carte/Badge)</span>
                  </div>
                </SelectItem>
                <SelectItem value="QR_DIGITAL" className="font-sans">
                  <div className="flex items-center gap-2">
                    <QrCode className="w-4 h-4 text-teal-600" />
                    <span>QR Digital (Email)</span>
                  </div>
                </SelectItem>
              </SelectContent>
            </Select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="token_uid" className="text-slate-700 font-bold">UID du Token</Label>
            {isPhysical && availableTokens && availableTokens.length > 0 ? (
              <>
                <Select
                  value={watch('token_uid') || ''}
                  onValueChange={(val) => setValue('token_uid', val, { shouldValidate: true })}
                >
                  <SelectTrigger className="rounded-xl border-slate-200 h-11 font-mono">
                    <SelectValue placeholder="Choisir un bracelet disponible" />
                  </SelectTrigger>
                  <SelectContent className="rounded-xl border-slate-200 shadow-xl max-h-[200px]">
                    {availableTokens.map((token: any) => (
                      <SelectItem key={token.id} value={token.token_uid} className="font-mono">
                        {token.token_uid}
                        {token.hardware_uid && (
                          <span className="text-slate-400 ml-2 text-xs">({token.hardware_uid})</span>
                        )}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                <p className="text-[10px] text-slate-400 font-sans">{availableTokens.length} bracelet(s) disponible(s)</p>
              </>
            ) : isPhysical && isLoadingTokens ? (
              <div className="flex items-center gap-2 h-11 px-3 border border-slate-200 rounded-xl">
                <Loader2 className="w-4 h-4 animate-spin text-slate-400" />
                <span className="text-sm text-slate-400 font-sans">Chargement des bracelets...</span>
              </div>
            ) : (
              <Input
                id="token_uid"
                {...register('token_uid')}
                placeholder="Scanner ou saisir l'identifiant"
                className="rounded-xl border-slate-200 h-11 focus:ring-schooltrack-primary font-mono"
              />
            )}
            {errors.token_uid && <p className="text-schooltrack-error text-[10px] font-bold mt-1 uppercase tracking-tight font-sans">{errors.token_uid.message}</p>}
          </div>

          {isReassign && (
            <div className="space-y-2 animate-in slide-in-from-top-2 duration-300">
              <Label htmlFor="justification" className="text-slate-700 font-bold flex items-center gap-2">
                <AlignLeft className="w-4 h-4 text-schooltrack-action" /> Justification (optionnelle)
              </Label>
              <Textarea 
                id="justification" 
                {...register('justification')} 
                placeholder="Ex: Bracelet perdu, changement de support..."
                className="rounded-xl border-slate-200 min-h-[80px] focus:ring-schooltrack-primary resize-none font-sans" 
              />
            </div>
          )}

          <DialogFooter className="gap-3 pt-4 border-t border-slate-50 mt-6">
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
              disabled={mutation.isPending}
              className="rounded-xl h-11 text-white px-8 flex-1 shadow-lg bg-schooltrack-primary hover:bg-blue-900 shadow-blue-900/20 transition-all active:scale-95 font-sans border-0"
            >
              {mutation.isPending ? (
                <>
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                  Traitement...
                </>
              ) : isReassign ? 'Réassigner' : 'Assigner'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
