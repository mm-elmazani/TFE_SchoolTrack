import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useNavigate } from 'react-router-dom';
import { useAuthStore } from '../store/authStore';
import { apiClient } from '@/api/axios';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Eye, EyeOff, Loader2, Lock, Mail, AlertCircle } from 'lucide-react';

const loginSchema = z.object({
  email: z.string().email('Email invalide'),
  password: z.string().min(1, 'Mot de passe requis'),
});

type LoginForm = z.infer<typeof loginSchema>;

export default function LoginScreen() {
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const navigate = useNavigate();
  const setAuth = useAuthStore((state) => state.setAuth);

  const { register, handleSubmit, formState: { errors } } = useForm<LoginForm>({
    resolver: zodResolver(loginSchema),
  });

  const onSubmit = async (data: LoginForm) => {
    setIsLoading(true);
    setError(null);
    try {
      const response = await apiClient.post('/api/v1/auth/login', data);
      const { access_token, user } = response.data;
      setAuth(access_token, user);
      navigate('/students', { replace: true });
    } catch (err: any) {
      setError(err.response?.data?.detail || 'Une erreur est survenue lors de la connexion');
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-schooltrack-neutral p-4">
      <Card className="w-full max-w-md shadow-2xl border-slate-200 overflow-hidden rounded-2xl">
        <div className="h-2 bg-schooltrack-primary w-full" />
        <CardHeader className="space-y-2 pb-6 pt-8">
          <CardTitle className="text-3xl font-bold tracking-tight text-schooltrack-primary">SchoolTrack</CardTitle>
          <CardDescription className="text-slate-500 text-base">
            Gérez vos élèves et voyages scolaires en toute sécurité.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
            {error && (
              <div className="p-4 bg-red-50 text-schooltrack-error border border-red-100 rounded-xl text-sm flex items-start gap-2 animate-in fade-in zoom-in duration-200">
                <AlertCircle className="h-5 w-5 shrink-0" />
                <span>{error}</span>
              </div>
            )}
            
            <div className="space-y-2">
              <Label htmlFor="email" className="text-slate-700 font-medium ml-1">Adresse Email</Label>
              <div className="relative group">
                <div className="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-slate-400 group-focus-within:text-schooltrack-primary transition-colors">
                  <Mail className="h-4 w-4" />
                </div>
                <Input
                  id="email"
                  type="email"
                  placeholder="nom@ecole.be"
                  autoComplete="email"
                  {...register('email')}
                  className={`pl-10 h-12 border-slate-200 rounded-xl transition-all focus:border-schooltrack-primary focus:ring-1 focus:ring-schooltrack-primary ${errors.email ? 'border-schooltrack-error bg-red-50/30' : ''}`}
                />
              </div>
              {errors.email && <p className="text-schooltrack-error text-xs font-medium mt-1 ml-1">{errors.email.message}</p>}
            </div>

            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <Label htmlFor="password" title="password" className="text-slate-700 font-medium ml-1">Mot de passe</Label>
              </div>
              <div className="relative group">
                <div className="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-slate-400 group-focus-within:text-schooltrack-primary transition-colors">
                  <Lock className="h-4 w-4" />
                </div>
                <Input
                  id="password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  {...register('password')}
                  className={`pl-10 h-12 border-slate-200 rounded-xl transition-all focus:border-schooltrack-primary focus:ring-1 focus:ring-schooltrack-primary ${errors.password ? 'border-schooltrack-error bg-red-50/30' : ''}`}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute inset-y-0 right-0 flex items-center pr-3 text-slate-400 hover:text-schooltrack-primary transition-colors"
                  aria-label={showPassword ? "Masquer le mot de passe" : "Afficher le mot de passe"}
                >
                  {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
              {errors.password && <p className="text-schooltrack-error text-xs font-medium mt-1 ml-1">{errors.password.message}</p>}
            </div>

            <Button 
              type="submit" 
              className="w-full h-12 bg-schooltrack-primary hover:bg-blue-900 text-white font-semibold rounded-xl shadow-lg shadow-blue-900/20 transition-all active:scale-[0.98] disabled:opacity-70" 
              disabled={isLoading}
            >
              {isLoading ? (
                <>
                  <Loader2 className="mr-2 h-5 w-5 animate-spin" />
                  Connexion en cours...
                </>
              ) : 'Se connecter'}
            </Button>
          </form>
          
          <div className="mt-10 pt-6 border-t border-slate-100 text-center">
            <p className="text-[10px] text-slate-400 uppercase tracking-widest font-medium">
              SchoolTrack &copy; 2026 - EPHEC
            </p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
