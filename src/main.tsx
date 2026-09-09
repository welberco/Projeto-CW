import { bootstrapApplication, findRootElement } from '@/app/bootstrap'
import '@/app/styles.css'

bootstrapApplication(findRootElement(), import.meta.env)
