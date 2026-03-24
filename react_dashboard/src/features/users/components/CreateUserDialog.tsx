import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { userApi } from '../api/userApi';
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
import { 
  Select, 
  SelectContent, 
  SelectItem, 
  SelectTrigger, 
  SelectValue 
} from '@/components/ui/select';
import { Loader2, Mail, Lock, User, Shield } from 'lucide-react';
import { cn } from '@/lib/utils';

const userSchema = z.object({
  first_name: z.string().min(1, 'Le prénom est requis'),
  last_name: z.string().min(1, 'Le nom est requis'),
  email: z.string().email('Email invalide'),
  password: z.string()
    .min(8, 'Au moins 8 caractères')
    .regex(/[A-Z]/, 'Au moins une majuscule')
    .regex(/\d/, 'Au moins un chiffre')
    .regex(/[^A-Za-z0-9]/, 'Au moins un caractère spécial'),
  role: z.enum(['DIRECTION', 'TEACHER', 'OBSERVER', 'ADMIN_TECH']),
});

type UserForm = z.infer<typeof userSchema>;

interface CreateUserDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function CreateUserDialog({ open, onOpenChange }: CreateUserDialogProps) {
  const [serverError, setServerError] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const { register, handleSubmit, formState: { errors }, reset, setValue, watch } = useForm<UserForm>({
    resolver: zodResolver(userSchema),
    defaultValues: {
      first_name: '',
      last_name: '',
      email: '',
      password: '',
      role: 'TEACHER',
    }
  });

  const selectedRole = watch('role');

  const createMutation = useMutation({
    mutationFn: userApi.create,
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['users'] });
      reset();
      onOpenChange(false);
    },
    onError: (error: any) => {
      const detail = error.response?.data?.detail;
      if (Array.isArray(detail)) {
        setServerError(detail[0]?.msg || 'Erreur de validation');
      } else {
        setServerError(detail || 'Erreur lors de la création');
      }
    }
  });

  const onSubmit = (data: UserForm) => {
    setServerError(null);
    createMutation.mutate(data);
  };

  return (
    <Dialog open={open} onOpenChange={(val) => {
      if (!val) reset();
      setServerError(null);
      onOpenChange(val);
    }}>
      <DialogContent className="sm:max-w-[500px] rounded-2xl font-sans border-0 shadow-2xl overflow-hidden p-0">
        <div className="h-2 bg-schooltrack-primary w-full" />
        <div className="p-6">
          <DialogHeader className="mb-6">
            <DialogTitle className="text-2xl font-bold text-schooltrack-primary font-heading">Ajouter un utilisateur</DialogTitle>
            <DialogDescription className="font-sans">
              Créez un nouveau compte pour un membre du personnel ou de la direction.
            </DialogDescription>
          </DialogHeader>

          <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
            {serverError && (
              <div className="p-4 bg-red-50 text-schooltrack-error border border-red-100 rounded-xl text-sm font-sans animate-in fade-in zoom-in duration-200">
                {serverError}
              </div>
            )}
            
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="last_name" className="text-slate-700 font-bold flex items-center gap-2">
                  <User className="w-4 h-4 text-schooltrack-action" /> Nom
                </Label>
                <Input 
                  id="last_name" 
                  {...register('last_name')} 
                  placeholder="ex: Dupont"
                  className={cn(
                    "rounded-xl border-slate-200 h-11 focus:ring-schooltrack-primary font-sans",
                    errors.last_name && "border-schooltrack-error bg-red-50/30"
                  )} 
                />
                {errors.last_name && <p className="text-schooltrack-error text-[10px] font-bold mt-1 uppercase">{errors.last_name.message}</p>}
              </div>

              <div className="space-y-2">
                <Label htmlFor="first_name" className="text-slate-700 font-bold flex items-center gap-2">
                  <User className="w-4 h-4 text-schooltrack-action" /> Prénom
                </Label>
                <Input 
                  id="first_name" 
                  {...register('first_name')} 
                  placeholder="ex: Jean"
                  className={cn(
                    "rounded-xl border-slate-200 h-11 focus:ring-schooltrack-primary font-sans",
                    errors.first_name && "border-schooltrack-error bg-red-50/30"
                  )} 
                />
                {errors.first_name && <p className="text-schooltrack-error text-[10px] font-bold mt-1 uppercase">{errors.first_name.message}</p>}
              </div>
            </div>

            <div className="space-y-2">
              <Label htmlFor="email" className="text-slate-700 font-bold flex items-center gap-2">
                <Mail className="w-4 h-4 text-schooltrack-action" /> Email professionnel
              </Label>
              <Input 
                id="email" 
                type="email"
                {...register('email')} 
                placeholder="nom.prenom@ecole.be"
                className={cn(
                  "rounded-xl border-slate-200 h-11 focus:ring-schooltrack-primary font-sans",
                  errors.email && "border-schooltrack-error bg-red-50/30"
                )} 
              />
              {errors.email && <p className="text-schooltrack-error text-[10px] font-bold mt-1 uppercase">{errors.email.message}</p>}
            </div>

            <div className="space-y-2">
              <Label htmlFor="password" className="text-slate-700 font-bold flex items-center gap-2">
                <Lock className="w-4 h-4 text-schooltrack-action" /> Mot de passe
              </Label>
              <Input 
                id="password" 
                type="password"
                {...register('password')} 
                placeholder="••••••••"
                className={cn(
                  "rounded-xl border-slate-200 h-11 focus:ring-schooltrack-primary font-sans",
                  errors.password && "border-schooltrack-error bg-red-50/30"
                )} 
              />
              <p className="text-[10px] text-slate-400 ml-1 font-medium italic">
                Min 8 car. , 1 majuscule, 1 chiffre, 1 car spécial
              </p>
              {errors.password && <p className="text-schooltrack-error text-[10px] font-bold mt-1 uppercase">{errors.password.message}</p>}
            </div>

            <div className="space-y-2">
              <Label htmlFor="role" className="text-slate-700 font-bold flex items-center gap-2">
                <Shield className="w-4 h-4 text-schooltrack-action" /> Rôle de l'utilisateur
              </Label>
              <Select 
                value={selectedRole} 
                onValueChange={(val: any) => setValue('role', val, { shouldValidate: true })}
              >
                <SelectTrigger className="rounded-xl border-slate-200 h-11 font-sans">
                  <SelectValue placeholder="Choisir un rôle" />
                </SelectTrigger>
                <SelectContent className="rounded-xl border-slate-200 shadow-xl">
                  <SelectItem value="DIRECTION" className="font-sans">Direction (Admin complet)</SelectItem>
                  <SelectItem value="TEACHER" className="font-sans">Enseignant (Gestion voyages/élèves)</SelectItem>
                  <SelectItem value="OBSERVER" className="font-sans">Observateur (Lecture seule)</SelectItem>
                  <SelectItem value="ADMIN_TECH" className="font-sans">Admin Tech (Maintenance)</SelectItem>
                </SelectContent>
              </Select>
              {errors.role && <p className="text-schooltrack-error text-[10px] font-bold mt-1 uppercase">{errors.role.message}</p>}
            </div>

            <DialogFooter className="gap-3 pt-6 border-t border-slate-50 mt-6">
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
                disabled={createMutation.isPending}
                className="rounded-xl h-11 bg-schooltrack-primary hover:bg-blue-900 text-white px-8 flex-1 shadow-lg shadow-blue-900/20 transition-all active:scale-95 font-sans border-0"
              >
                {createMutation.isPending ? (
                  <>
                    <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                    Création...
                  </>
                ) : 'Créer le compte'}
              </Button>
            </DialogFooter>
          </form>
        </div>
      </DialogContent>
    </Dialog>
  );
}
